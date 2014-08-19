module Dynflow
  module Testing
    class DummyExecutionPlan
      extend Mimic
      mimic! ExecutionPlan

      attr_reader :id, :planned_plan_steps, :planned_run_steps, :planned_finalize_steps

      def initialize
        @id                       = Testing.get_id.to_s
        @planned_plan_steps       = []
        @planned_run_steps        = []
        @planned_finalize_steps   = []
        @planned_action_stubbers  = {}
      end

      def world
        @world ||= DummyWorld.new
      end

      # Allows modify the DummyPlannedAction returned by plan_action
      def stub_planned_action(klass, &block)
        @planned_action_stubbers[klass] = block
      end

      def add_plan_step(klass, _)
        dummy_planned_action(klass).tap do |action|
          @planned_plan_steps << action
        end
      end

      def add_run_step(action)
        @planned_run_steps << action
        action
      end

      def add_finalize_step(action)
        @planned_finalize_steps << action
        action
      end

      def dummy_planned_action(klass)
        DummyPlannedAction.new(klass).tap do |action|
          if planned_action_stubber = @planned_action_stubbers[klass]
            planned_action_stubber.call(action)
          end
        end
      end

      def planning_log=(thing)
        @planning_log = thing
      end

      def planning_log
        @planning_log
      end

      def switch_flow(*args, &block)
        block.call
      end
    end
  end
end
