module Dynflow
  class Manager



    attr_accessor :persistence_driver, :logger, :initiator, :transaction_driver,
                  :serialization_driver

    def initialize(params={})
      params.each{|k,v| self.send("#{k.to_s}=",v)}

      #set defaults
      self.logger ||= ::Logger
      self.initiator ||= Dynflow::Initiators::ExecutorInitiator.new()
    end



    def trigger(action_class, *args)
      execution_plan = nil
      execute_transaction do
        execution_plan = prepare_execution_plan(action_class, *args)
        rollback_transaction if execution_plan.status == 'error'
      end
      persist_plan(execution_plan)
      unless execution_plan.status == 'error'
        @initiator.start(execution_plan.run_plan)
      end
      return execution_plan
    end

    # @return [Dynflow::ExecutionPlan]
    def load_execution_plan(persistence_id)
      if persistence_driver
        persisted_plan = persistence_driver.persistence_class.persisted_plan(persistence_id)

        plan_steps = persisted_plan.plan_step_ids.map do |step_id|
          load_step_without_plan(step_id)
        end

        run_steps = persisted_plan.run_step_ids.map do |step_id|
          load_step_without_plan(step_id)
        end

        finalize_steps = persisted_plan.finalize_step_ids.map do |step_id|
          load_step_without_plan(step_id)
        end

        #set the execution plan on the step
        (plan_steps + run_steps + finalize_steps).each do |step|
          step.execution_plan = persisted_plan
        end

        execution_plan = ExecutionPlan.new(plan_steps, run_steps, finalize_steps)
        execution_plan.run_plan = restore_run_plan(persisted_plan.serialized_run_plan)
        execution_plan.status = persisted_plan.status
        execution_plan.persistence = persisted_plan

        return execution_plan
      else
        raise "No persistence driver configured"
      end
    end

    def load_step(persistence_id)
      step = load_step_without_plan(persistence_id)
      plan = load_execution_plan(persistence_id)
      return plan.steps.select{|s| s.persistence_id == persistence_id}.first
    end



    private

    #Load a persisted step, but don't try to load its plan and associate it
    def load_step_without_plan(persistence_id)
      if persistence_driver
        persistence_driver.persistence_class.persisted_step(persistence_id)
      else
        raise "No persistence driver configured"
      end
    end

    def restore_run_plan(serialized_run_plan)
      step_type = serialized_run_plan['step_type'].constantize
      if step_type.ancestors.include?(Step)
        return load_step_without_plan(serialized_run_plan['persistence_id'])
      else
        steps = serialized_run_plan['steps'].map do |serialized_step|
          restore_run_plan(serialized_step)
        end
        return step_type.new(steps)
      end
    end

    def persist_plan(execution_plan)
      if self.persistence_driver
        serialization = self.serialization_driver
        raise "No serialization driver defined" if serialization.nil?
        self.persistence_driver.persistence_class.persist(execution_plan) do |persisted_plan|
          persisted_plan.serialized_run_plan = serialization.serialize_run_plan(execution_plan.run_plan)
        end
      end
    end

    def prepare_execution_plan(action_class, *args)
      action_class.plan(*args).execution_plan
    end


    def execute_transaction
      if self.transaction_driver
        ret = nil
        transaction_driver.transaction do
          ret = yield
        end
        return ret
      else
        return yield
      end
    end

    def rollback_transaction
      transaction_driver.rollback if self.transaction_driver
    end

  end
end
