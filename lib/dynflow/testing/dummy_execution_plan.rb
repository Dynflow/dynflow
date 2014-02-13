module Dynflow
  module Testing
    class DummyExecutionPlan
      extend Mimic
      mimic! ExecutionPlan

      attr_reader :id, :planned_plan_steps, :planned_run_steps, :planned_finalize_steps

      def initialize
        @id                     = Testing.get_id.to_s
        @planned_plan_steps     = []
        @planned_run_steps      = []
        @planned_finalize_steps = []
      end

      def world
        @world ||= DummyWorld.new
      end

      def add_run_step(action)
        @planned_run_steps << action
        action
      end

      def add_finalize_step(action)
        @planned_finalize_steps << action
        action
      end

      def add_plan_step(klass, action)
        @planned_plan_steps << action = DummyPlannedAction.new(klass)
        action
      end

      def switch_flow(*args, &block)
        block.call
      end
    end
  end
end
