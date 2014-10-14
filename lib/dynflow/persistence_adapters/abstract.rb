module Dynflow
  module PersistenceAdapters
    class Abstract
      def pagination?
        false
      end

      def transaction
        raise NotImplementedError
      end

      def filtering_by
        []
      end

      def ordering_by
        []
      end

      # @option options [Integer] page index of the page (starting at 0)
      # @option options [Integer] per_page the number of the items on page
      # @option options [Symbol] order_by name of the column to use for ordering
      # @option options [true, false] desc set to true if order should be descending
      # @option options [Hash{ Symbol => Object,Array<object> }] filters hash represents
      #   set of allowed values for a given key representing column
      def find_execution_plans(options = {})
        raise NotImplementedError
      end

      def load_execution_plan(execution_plan_id)
        raise NotImplementedError
      end

      def save_execution_plan(execution_plan_id, value)
        raise NotImplementedError
      end

      def load_step(execution_plan_id, step_id)
        raise NotImplementedError
      end

      def save_step(execution_plan_id, step_id, value)
        raise NotImplementedError
      end

      def load_action(execution_plan_id, action_id)
        raise NotImplementedError
      end

      def save_action(execution_plan_id, action_id, value)
        raise NotImplementedError
      end

      def find_worlds(options)
        raise NotImplementedError
      end

      def save_world(id, data)
        raise NotImplementedError
      end

      def delete_world(id)
        raise NotImplementedError
      end

      def save_executor_allocation(executor_allocation)
        raise NotImplementedError
      end

      def find_executor_allocations(options)
        raise NotImplementedError
      end

      def delete_executor_allocations(options)
        raise NotImplementedError
      end

      # for debug purposes
      def to_hash
        raise NotImplementedError
      end

      def pull_envelopes(receiver_id)
        raise NotImplementedError
      end

      def push_envelope(envelope)
        raise NotImplementedError
      end
    end
  end
end
