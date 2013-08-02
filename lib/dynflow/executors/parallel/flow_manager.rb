module Dynflow
  module Executors
    class Parallel < Abstract
      class FlowManager
        include Algebrick::TypeCheck

        attr_reader :execution_plan, :cursor_index, :flow

        def initialize(execution_plan, flow)
          @execution_plan    = is_kind_of! execution_plan, ExecutionPlan
          @flow              = is_kind_of! flow, Flows::Abstract
          @cursor_index      = {}
          @cursor            = build_cursor(flow, nil, nil)
          @steps_in_progress = Set.new
        end

        def done?
          @cursor.done?
        end

        def run_flow?
          @execution_plan.run_flow == @flow
        end

        # @return [Set] of steps to continue with
        def what_is_next(flow_step)
          execution_plan.steps[flow_step.id] = flow_step
          execution_plan.save

          cursor_index[flow_step.id].flow_step_done(flow_step.state)
          next_steps
        end

        # @return [Set] of steps to continue with
        def start
          next_steps.tap { |steps| raise 'invalid state' if steps.empty? && !done? }
        end

        private

        # @return [Set] of steps to continue with
        def next_steps
          new_flow_step_ids = @cursor.next_step_ids - @steps_in_progress
          @steps_in_progress.merge new_flow_step_ids

          new_flow_step_ids.map { |id| @execution_plan.steps[id].clone }
        end

        def build_cursor(flow, parent, requires)
          is_kind_of! flow, Flows::Abstract
          case flow
          when Flows::Concurrence
            concurrence = Cursor.new(self, parent, requires)
            flow.sub_flows.map { |flow| build_cursor(flow, concurrence, nil) }
            concurrence
          when Flows::Sequence
            raise 'empty Sequences are not supported' if flow.sub_flows.empty?
            before_last = flow.sub_flows[0..-2].inject(nil) do |req, flow|
              build_cursor flow, nil, req
            end
            raise 'multiple requires is not supported' if requires
            build_cursor flow.sub_flows.last, parent, before_last if flow.sub_flows.last
          when Flows::Atom
            Cursor.new(self, parent, requires, flow.step_id).tap { |c| @cursor_index[flow.step_id] = c }
          end
        end
      end
    end
  end
end
