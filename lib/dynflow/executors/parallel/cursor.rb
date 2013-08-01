module Dynflow
  module Executors
    class Parallel < Abstract
      class Cursor
        include Algebrick::TypeCheck

        attr_reader :manager, :parent, :depends_on, :depended_by, :children, :flow_step_id

        def initialize(manager, parent, depends_on, flow_step_id = nil)
          @manager        = is_kind_of! manager, FlowManager
          @parent         = parent
          @children       = Set.new
          @done           = false
          @flow_step_id   = flow_step_id
          @flow_step_done = false
          @depends_on     = depends_on
          @depended_by    = nil

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

        def done?
          @done
        end

        def flow_step_done
          @flow_step_done = true
          notify
        end

        # @return [Set] of step_ids to continue with
        def what_is_next
          return Set.new if done?
          return @depends_on.what_is_next if @depends_on && !@depends_on.done?
          return @children.inject(Set.new) { |s, ch| s.merge ch.what_is_next }.flatten unless @children.empty?

          Set.new [flow_step_id].compact
        end

        def to_hash
          { children:       @children.map(&:to_hash),
            depends_on:     (@depends_on.to_hash if @depends_on),
            flow_step_id:   @flow_step_id,
            flow_step_done: @flow_step_done,
            done:           @done }
        end

        protected

        def notify
          if depends_on_satisfied? && children_are_done? && flow_step_done?
            @done = true
            @depended_by.notify if @depended_by
            @parent.notify if @parent
          end
        end

        private

        def depends_on_satisfied?
          @depends_on.nil? || @depends_on.done?
        end

        def children_are_done?
          @children.all? { |ch| ch.done? }
        end

        def flow_step_done?
          @flow_step_id.nil? || @flow_step_done
        end
      end
    end
  end
end
