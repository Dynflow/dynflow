module Dynflow
  class World
    module Invalidation
      # Invalidate another world, that left some data in the runtime,
      # but it's not really running
      #
      # @param world [Coordinator::ClientWorld, Coordinator::ExecutorWorld] coordinator record
      #   left behind by the world we're trying to invalidate
      # @return [void]
      def invalidate(world)
        Type! world, Coordinator::ClientWorld, Coordinator::ExecutorWorld
        coordinator.acquire(Coordinator::WorldInvalidationLock.new(self, world)) do
          if world.is_a? Coordinator::ExecutorWorld
            old_execution_locks = coordinator.find_locks(class: Coordinator::ExecutionLock.name,
                                                         owner_id: "world:#{world.id}")

            coordinator.deactivate_world(world)

            old_execution_locks.each do |execution_lock|
              invalidate_execution_lock(execution_lock)
            end
          end

          coordinator.delete_world(world)
        end
      end

      # Invalidate an execution lock, left behind by a executor that
      # was executing an execution plan when it was terminated.
      #
      # @param execution_lock [Coordinator::ExecutionLock] the lock to invalidate
      # @return [void]
      def invalidate_execution_lock(execution_lock)
        with_valid_execution_plan_for_lock(execution_lock) do |plan|
          plan.execution_history.add('terminate execution', execution_lock.world_id)

          plan.steps.values.each do |step|
            if step.state == :running
              step.error = ExecutionPlan::Steps::Error.new("Abnormal termination (previous state: #{step.state})")
              step.state = :error
              step.save
            end
          end

          plan.update_state(:paused) if plan.state == :running
          plan.save
          coordinator.release(execution_lock)

          if plan.error?
            rescue_id = plan.rescue_plan_id
            execute(rescue_id) if rescue_id
          else
            if coordinator.find_worlds(true).any? # Check if there are any executors
              client_dispatcher.tell([:dispatch_request,
                                      Dispatcher::Execution[execution_lock.execution_plan_id],
                                      execution_lock.client_world_id,
                                      execution_lock.request_id])
            end
          end
        end
      rescue Errors::PersistenceError
        logger.error "failed to write data while invalidating execution lock #{execution_lock}"
      end

      # Tries to load an execution plan using id stored in the
      # lock. If the execution plan cannot be loaded or is invalid,
      # the lock is released. If the plan gets loaded successfully, it
      # is yielded to a given block.
      #
      # @param execution_lock [Coordinator::ExecutionLock] the lock for which we're trying
      #   to load the execution plan
      # @yieldparam [ExecutionPlan] execution_plan the successfully loaded execution plan
      # @return [void]
      def with_valid_execution_plan_for_lock(execution_lock)
        begin
          plan = persistence.load_execution_plan(execution_lock.execution_plan_id)
        rescue => e
          if e.is_a?(KeyError)
            logger.error "invalidated execution plan #{execution_lock.execution_plan_id} missing, skipping"
          else
            logger.error e
            logger.error "unexpected error when invalidating execution plan #{execution_lock.execution_plan_id}, skipping"
          end
          coordinator.release(execution_lock)
          coordinator.release_by_owner(execution_lock.execution_plan_id)
          return
        end
        unless plan.valid?
          logger.error "invalid plan #{plan.id}, skipping"
          coordinator.release(execution_lock)
          coordinator.release_by_owner(execution_lock.execution_plan_id)
          return
        end
        yield plan
      end

      # Performs world validity checks
      #
      # @return [Integer] number of invalidated worlds
      def perform_validity_checks
        world_invalidation_result = worlds_validity_check
        locks_validity_check
        world_invalidation_result.values.select { |result| result == :invalidated }.size
      end

      # Checks if all worlds are valid and optionally invalidates them
      #
      # @param auto_invalidate [Boolean] whether automatic invalidation should be performed
      # @param worlds_filter [Hash] hash of filters to select only matching worlds
      # @return [Hash{String=>Symbol}] hash containg validation results, mapping world id to a result
      def worlds_validity_check(auto_invalidate = true, worlds_filter = {})
        worlds = coordinator.find_worlds(false, worlds_filter)

        world_checks = worlds.reduce({}) do |hash, world|
          hash.update(world => ping_without_cache(world.id, self.validity_check_timeout))
        end
        world_checks.values.each(&:wait)

        results = {}
        world_checks.each do |world, check|
          if check.success?
            result = :valid
          else
            if auto_invalidate
              begin
                invalidate(world)
                result = :invalidated
              rescue => e
                logger.error e
                result = e.message
              end
            else
              result = :invalid
            end
          end
          results[world.id] = result
        end

        unless results.values.all? { |result| result == :valid }
          logger.error "invalid worlds found #{results.inspect}"
        end

        return results
      end

      # Cleans up locks which don't have a resource
      #
      # @return [Array<Coordinator::Lock>] the removed locks
      def locks_validity_check
        orphaned_locks = coordinator.clean_orphaned_locks

        unless orphaned_locks.empty?
          logger.error "invalid coordinator locks found and invalidated: #{orphaned_locks.inspect}"
        end

        return orphaned_locks
      end
    end
  end
end
