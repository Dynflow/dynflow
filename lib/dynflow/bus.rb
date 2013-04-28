require 'active_support/inflector'
require 'forwardable'
module Dynflow
  class Bus

    class << self
      extend Forwardable

      def_delegators :impl, :wait_for, :process, :trigger, :finalize

      def impl
        @impl ||= Bus::MemoryBus.new
      end
      attr_writer :impl
    end

    def prepare_execution_plan(action_class, *args)
      action_class.plan(*args)
    end

    def run_execution_plan(execution_plan)
      execution_plan.actions.map do |action|
        return self.process(action)
      end
    end

    def finalize(outputs)
      outputs.each do |action|
        if action.respond_to?(:finalize)
          action.finalize(outputs)
        end
      end
    end

    def process(action)
      # TODO: here goes the message validation
      action.run if action.respond_to?(:run)
      return action
    end

    def wait_for(*args)
      raise NotImplementedError, 'Abstract method'
    end

    def logger
      @logger ||= Dynflow::Logger.new(self.class)
    end

    class MemoryBus < Bus

      def trigger(action_class, *args)
        execution_plan = prepare_execution_plan(action_class, *args)
        outputs = run_execution_plan(execution_plan)
        self.finalize(outputs)
      end

    end

    # uses Rails API for db features
    # encapsulates the planning and finalization phase into
    class RailsBus < Bus

      def trigger(action_class, *args)
        ActiveRecord::Base.transaction do
          execution_plan = prepare_execution_plan(action_class, *args)
        end
        outputs = run_execution_plan(execution_plan)
        ActiveRecord::Base.transaction do
          self.finalize(outputs)
        end
      end

      # performs the planning phase of an action, but rollbacks any db
      # changes done in this phase. Returns the resulting execution
      # plan. Suitable for debugging.
      def preview_execution_plan(action_class, *args)
        ActiveRecord::Base.transaction do
          execution_plan = prepare_execution_plan(action_class, *args)
          raise ActiveRecord::Rollback
        end
        return execution_plan
      end

    end

  end
end
