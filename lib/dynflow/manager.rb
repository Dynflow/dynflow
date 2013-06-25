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
