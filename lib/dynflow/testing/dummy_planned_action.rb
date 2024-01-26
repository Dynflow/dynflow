# frozen_string_literal: true

module Dynflow
  module Testing
    class DummyPlannedAction
      attr_accessor :output, :plan_input
      include Mimic

      def initialize(klass)
        mimic! klass
        @output = ExecutionPlan::OutputReference.new(
          Testing.get_id.to_s, Testing.get_id, Testing.get_id)
      end

      def execute(execution_plan, event, from_subscription, *args)
        @plan_input = args
        self
      end

      def run_step_id
        @run_step_id ||= Testing.get_id
      end
    end
  end
end
