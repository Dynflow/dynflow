require 'active_support/inflector'
require 'forwardable'
module Dynflow
  class Bus

    class << self
      extend Forwardable

      def_delegators :impl, :trigger, :resume, :skip, :preview_execution_plan,
        :persisted_plans, :persisted_plan, :persisted_step

      def impl
        @impl ||= Bus.new
      end

      # the default bus can be specified
      attr_writer :impl
    end

    # Entry point for running an action
    # @returns [Executors::Future, false] false is returned on error,
    #     otherwise a_future is returned which is set after execution_plan's finalization
    def trigger(action_class, *args)
      execution_plan = nil
      in_transaction_if_possible do
        execution_plan = prepare_execution_plan(action_class, *args)
        rollback_transaction if execution_plan.status == 'error'
      end
      persist_plan_if_possible(execution_plan)

      return Executors::Future.new.set(execution_plan) if execution_plan.status == 'error'
      execute(execution_plan) # TODO check for error
    end

    def prepare_execution_plan(action_class, *args)
      action_class.plan(*args).execution_plan
    end

    # execution and finalizaition. Usable for resuming paused plan
    # as well as starting from scratch
    def execute(execution_plan)
      execution_driver.run self, execution_plan
    end

    alias_method :resume, :execute

    def skip(step)
      step.status = 'skipped'
      step.persist
    end

    def execution_driver
      @execution_driver ||= Executors::PooledSequential.new
    end

    def transaction_driver
      nil
    end

    def in_transaction_if_possible
      if transaction_driver
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
      transaction_driver.rollback if transaction_driver
    end

    def persistence_driver
      nil
    end

    def persist_plan_if_possible(execution_plan)
      if persistence_driver
        # TODO: the whole serialization logic should not be dependent on the
        # persistence driver
        persistence_driver.persist(execution_plan) do |persisted_plan|
          persisted_plan.serialized_run_plan = self.serialize_run_plan(execution_plan.run_plan)
        end
      end
    end

    # @return [Array<Dynflow:ExecutionPlan>]
    def persisted_plans(status = nil, search_options = {})
      if persistence_driver
        persistence_driver.persisted_plans(status, search_options).map do |persisted_plan|
          self.persisted_plan(persisted_plan.persistence_id)
        end
      else
        []
      end
    end

    # @return [Dynflow::ExecutionPlan]
    def persisted_plan(persistence_id)
      if persistence_driver
        with_persisted_steps_cache do
          persisted_plan = persistence_driver.persisted_plan(persistence_id)

          plan_steps = persisted_plan.plan_step_ids.map do |step_id|
            persisted_step(step_id)
          end

          run_steps = persisted_plan.run_step_ids.map do |step_id|
            persisted_step(step_id)
          end

          finalize_steps = persisted_plan.finalize_step_ids.map do |step_id|
            persisted_step(step_id)
          end

          execution_plan = ExecutionPlan.new(plan_steps, run_steps, finalize_steps)
          execution_plan.run_plan = restore_run_plan(persisted_plan.serialized_run_plan)
          execution_plan.status = persisted_plan.status
          execution_plan.persistence = persisted_plan

          return execution_plan
        end
      end
    end

    def persisted_step(persistence_id)
      if persistence_driver
        cache = Thread.current[:dynflow_persisted_steps_cache]
        if cache && cache[persistence_id]
          step = cache[persistence_id]
        else
          step = persistence_driver.persisted_step(persistence_id)
          cache[persistence_id] = step if cache
        end
        return step
      end
    end

    def with_persisted_steps_cache
      Thread.current[:dynflow_persisted_steps_cache] = {}
      yield
    ensure
      Thread.current[:dynflow_persisted_steps_cache] = nil
    end

    def serialize_run_plan(run_plan)
      out = {}
      out['step_type'] = run_plan.class.name
      if run_plan.is_a? Dynflow::Step
        out['persistence_id'] = run_plan.persistence.id
      else
        out['steps'] = run_plan.steps.map { |step| serialize_run_plan(step) }
      end
      return out
    end

    def restore_run_plan(serialized_run_plan)
      step_type = serialized_run_plan['step_type'].constantize
      if step_type.ancestors.include?(Dynflow::Step)
        return persisted_step(serialized_run_plan['persistence_id'])
      else
        steps = serialized_run_plan['steps'].map do |serialized_step|
          restore_run_plan(serialized_step)
        end
        return step_type.new(steps)
      end
    end

    # performs the planning phase of an action, but rollbacks any db
    # changes done in this phase. Returns the resulting execution
    # plan. Suitable for debugging.
    def preview_execution_plan(action_class, *args)
      unless transaction_driver
        raise "Bus doesn't know how to run in transaction"
      end

      execution_plan = nil
      transaction_driver.transaction do
        execution_plan = prepare_execution_plan(action_class, *args)
        transaction_driver.rollback
      end
      return execution_plan
    end

    def logger
      @logger ||= Dynflow::Logger.new(self.class)
    end

    class ActiveRecordTransaction
      class << self

        def transaction(&block)
          ActiveRecord::Base.transaction(&block)
        end

        def rollback
          raise ActiveRecord::Rollback
        end

      end
    end

    class ActiveRecordBus < Bus

      def initialize
        require 'dynflow/persistence/active_record/persisted_plan'
        require 'dynflow/persistence/active_record/persisted_step'
      end

      def transaction_driver
        ActiveRecordTransaction
      end

      def persistence_driver
        Dynflow::Persistence::ActiveRecord::PersistedPlan
      end

      def self.migrations_path
        File.expand_path('../../../db/migrate', __FILE__)
      end

      def self.bootstrap_migrations(app)
        app.config.paths['db/migrate'] << self.migrations_path
      end

    end

  end
end
