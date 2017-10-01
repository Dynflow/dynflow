module Dynflow
  class Action
    module Singleton
      def plan(*args)
        singleton_lock!
        plan_self(*args)
      end

      def run(event = nil)
        # At the beginning of the run phase, verify we have the lock or fail
        validate_singleton_lock!
      end

      def finalize
        singleton_unlock!
      end

      private

      def with_valid_singleton_lock
        validate_singleton_lock!
        yield
      end

      def validate_singleton_lock!
        singleton_lock! unless holds_singleton_lock?
      end

      def singleton_lock!
        world.coordinator.acquire(singleton_lock)
      rescue Dynflow::Coordinator::LockError
        fail "Action #{self.class.name} is already active"
      end

      def singleton_unlock!
        world.coordinator.release(singleton_lock) if holds_singleton_lock?
      end

      def holds_singleton_lock?
        # Get locks for this action, there should be none or one
        lock_filter = singleton_lock_class.unique_filter(self.class.name)
        present_locks = world.coordinator.find_locks lock_filter
        !present_locks.empty? && present_locks.first.owner_id == execution_plan_id
      end

      def singleton_lock_class
        ::Dynflow::Coordinator::SingletonActionLock
      end

      def singleton_lock
        singleton_lock_class.new(self.class.name, execution_plan_id)
      end

      def error!(*args)
        singleton_unlock!
        super
      end
    end
  end
end
