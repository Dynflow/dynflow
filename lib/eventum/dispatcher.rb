module Eventum
  class Dispatcher
    class << self
      def finalizers
        @finalizers ||= Hash.new { |h, k| h[k] = [] }
      end

      def actions_for_event(event)
        Action.actions.find_all do |action|
          case action.subscribe
          when Hash
            action.subscribe.keys.include?(event.class)
          when Array
            action.subscribe.include?(event.class)
          else
            action.subscribe == event.class
          end
        end
      end

      def execution_plan_for(event)
        dep_tree = actions_for_event(event).reduce({}) do |h, action_class|
          h.update(action_class => action_class.require)
        end

        ordered_actions = []
        while (no_dep_actions = dep_tree.find_all { |part, require| require.nil? }).any? do
          no_dep_actions = no_dep_actions.map(&:first)
          ordered_actions.concat(no_dep_actions.sort_by(&:name))
          no_dep_actions.each { |part| dep_tree.delete(part) }
          dep_tree.keys.each do |part|
            dep_tree[part] = nil if ordered_actions.include?(dep_tree[part])
          end
        end

        if (unresolved = dep_tree.find_all { |_, require| require }).any?
          raise 'The following deps were unresolved #{unresolved.inspect}'
        end

        execution_plan = []
        ordered_actions.each do |action_class|
          if action_class.subscribe.is_a?(Hash)
            mapping = action_class.subscribe[event.class].to_s
            if event[mapping]
              event[mapping].each do |subinput|
                execution_plan << [action_class, subinput]
              end
            end
          else
            execution_plan << [action_class, event.data]
          end
        end
        return execution_plan
      end
    end
  end
end
