module Dynflow
  module Executors
    class Parallel < Abstract
      class Cursor
        include Algebrick::TypeCheck

        attr_reader :manager, :parent, :depends_on, :depended_by, :children, :flow_step_id

        def initialize(manager, parent, depends_on, flow_step_id = nil)
          @manager            = is_kind_of! manager, FlowManager
          @parent             = parent
          @children           = Set.new
          @flow_step_continue = true
          @flow_step_id       = flow_step_id
          @flow_step_done     = false
          @depends_on         = depends_on
          @depended_by        = nil

          depends_on.depended_by = self if depends_on
          parent.add_child self if parent
        end

        def depended_by=(something)
          raise 'depended_by is already set' if @depended_by
          @depended_by = something
        end

        def add_child(child)
          raise 'cursor with flow_step_id cannot have children' if flow_step_id
          @children.add?(child) || raise("#{child} is already present - invalid state")
        end

        def flow_step_done(flow_step_state)
          @flow_step_continue = false if [:error, :suspended].include? flow_step_state
          @flow_step_done = true
          drop_cache
        end

        def to_hash
          { flow_step_id:       @flow_step_id,
            flow_step_done:     @flow_step_done,
            flow_step_continue: @flow_step_continue,
            done?:              done?,
            continue?:          continue?,
            next_step_ids:      next_step_ids.to_a,
            children:           @children.map(&:to_hash),
            depends_on:         (@depends_on.to_hash if @depends_on) }
        end

        def done?
          if @done_cache.nil?
            not_continuable_depends_on = @depends_on && !@depends_on.continue?
            no_undone_child            = !@children.empty? && @children.all?(&:done?)

            @done_cache = not_continuable_depends_on || @flow_step_done || no_undone_child
          else
            @done_cache
          end
        end

        def continue?
          if @continue_cache.nil?
            continuable_depends_on = !@depends_on || @depends_on.continue?
            no_failed_child        = @children.all?(&:continue?)

            @continue_cache = continuable_depends_on && @flow_step_continue && no_failed_child
          else
            @continue_cache
          end
        end

        # @return [Set] of step_ids to continue with
        def next_step_ids
          if done?
            Set.new
          elsif @depends_on && !@depends_on.done?
            @depends_on.next_step_ids
          elsif !@children.empty?
            @children.inject(Set.new) { |s, ch| s.merge ch.next_step_ids }.flatten
          elsif flow_step_id
            Set.new [flow_step_id]
          else
            raise 'there is a bug in the condition above'
          end
        end

        protected

        def drop_cache
          @done_cache = @continue_cache = nil
          @depended_by.drop_cache if @depended_by
          @parent.drop_cache if @parent
        end

      end
    end
  end
end
