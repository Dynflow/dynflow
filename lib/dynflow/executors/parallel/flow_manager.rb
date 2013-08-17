module Dynflow
  module Executors
    class Parallel < Abstract
      class FlowManager
        include Algebrick::TypeCheck

        attr_reader :execution_plan, :cursor_index

        def initialize(execution_plan, flow)
          @execution_plan    = is_kind_of! execution_plan, ExecutionPlan
          @flow              = flow
          @cursor_index      = {}
          @cursor            = build_root_cursor
        end

        def done?
          @cursor.done?
        end

        # @return [Set] of steps to continue with
        def what_is_next(flow_step)
          execution_plan.steps[flow_step.id] = flow_step
          execution_plan.save
          return [] if flow_step.state == :suspended

          success = flow_step.state != :error
          return cursor_index[flow_step.id].what_is_next(flow_step, success)
        end

        # @return [Set] of steps to continue with
        def start
          return @cursor.what_is_next.tap do |steps|
            raise 'invalid state' if steps.empty? && !done?
          end
        end

        private

        def build_root_cursor
          # the root cursor has to always run against sequence
          sequence = @flow.is_a?(Flows::Sequence) ? @flow : Flows::Sequence.new([@flow])
          return SequenceCursor.new(self, sequence, nil)
        end
      end
    end
  end
end
