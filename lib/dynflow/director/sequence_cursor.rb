module Dynflow
  class Director
    class SequenceCursor

      def initialize(flow_manager, sequence, parent_cursor = nil)
        @flow_manager    = flow_manager
        @sequence        = sequence
        @parent_cursor   = parent_cursor
        @todo            = []
        @index           = -1 # starts before first element
        @no_error_so_far = true
      end

      # @param [ExecutionPlan::Steps::Abstract, SequenceCursor] work
      #   step or sequence cursor that was done
      # @param [true, false] success was the work finished successfully
      # @return [Array<Integer>] new step_ids that can be done next
      def what_is_next(work = nil, success = true)
        unless work.nil? || @todo.delete(work)
          raise "marking as done work that was not expected: #{work.inspect}"
        end

        @no_error_so_far &&= success

        if done_here?
          return next_steps
        else
          return []
        end
      end

      # return true if we can't move the cursor further, either when
      # everyting is done in the sequence or there was some failure
      # that prevents us from moving
      def done?
        (!@no_error_so_far && done_here?) || @index == @sequence.size
      end

      protected

      # steps we can do right now without waiting for anything
      def steps_todo
        @todo.map do |item|
          case item
          when SequenceCursor
            item.steps_todo
          else
            item
          end
        end.flatten
      end

      def move
        @index   += 1
        next_flow = @sequence.sub_flows[@index]
        add_todo(next_flow)
      end

      private

      def done_here?
        @todo.empty?
      end

      def next_steps
        move if @no_error_so_far
        return steps_todo unless done?
        if @parent_cursor
          return @parent_cursor.what_is_next(self, @no_error_so_far)
        else
          return []
        end
      end

      def add_todo(flow)
        case flow
        when Flows::Sequence
          @todo << SequenceCursor.new(@flow_manager, flow, self).tap do |cursor|
            cursor.move
          end
        when Flows::Concurrence
          flow.sub_flows.each { |sub_flow| add_todo(sub_flow) }
        when Flows::Atom
          @flow_manager.cursor_index[flow.step_id] = self
          @todo << @flow_manager.execution_plan.steps[flow.step_id]
        end
      end

    end
  end
end
