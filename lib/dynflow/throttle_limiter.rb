module Dynflow
  class ThrottleLimiter

    attr_reader :core

    def initialize(world)
      @world = world
      spawn
    end

    def handle_plans!(*args)
      core.ask!([:handle_plans, *args])
    end

    def cancel!(plan_id)
      core.tell([:cancel, plan_id])
    end

    def terminate
      core.ask(:terminate!)
    end

    def observe(parent_id = nil)
      core.ask!([:observe, parent_id])
    end

    def core_class
      Core
    end

    private

    def spawn
      Concurrent.future.tap do |initialized|
        @core = core_class.spawn(:name => 'throttle-limiter',
                                 :args => [@world],
                                 :initialized => initialized)
      end
    end

    class Core < Actor
      def initialize(world)
        @world = world
        @semaphores = {}
      end

      def handle_plans(parent_id, planned_ids, failed_ids, semaphores_hash)
        @semaphores[parent_id] = create_semaphores(semaphores_hash)
        set_up_clock_for(parent_id, true)

        failed = failed_ids.map do |plan_id|
          ::Dynflow::World::Triggered[plan_id, Concurrent.future].tap do |triggered|
            execute_triggered(triggered)
          end
        end

        planned_ids.map do |child_id|
          ::Dynflow::World::Triggered[child_id, Concurrent.future].tap do |triggered|
            triggered.future.on_completion! { self << [:release, parent_id] }
            execute_triggered(triggered) if @semaphores[parent_id].wait(triggered)
          end
        end + failed
      end

      def observe(parent_id = nil)
        if parent_id.nil?
          @semaphores.reduce([]) do |acc, cur|
            acc << { cur.first => cur.last.waiting }
          end
        elsif @semaphores.key? parent_id
          @semaphores[parent_id].waiting
        else
          []
        end
      end

      def release(plan_id, key = :level)
        return unless @semaphores.key? plan_id
        set_up_clock_for(plan_id) if key == :time
        semaphore = @semaphores[plan_id]
        semaphore.release(1, key) if semaphore.children.key?(key)
        if semaphore.has_waiting? && semaphore.get == 1
          execute_triggered(semaphore.get_waiting)
        end
        @semaphores.delete(plan_id) unless semaphore.has_waiting?
      end

      def cancel(parent_id, reason = nil)
        if @semaphores.key?(parent_id)
          reason ||= 'The task was cancelled.'
          @semaphores[parent_id].waiting.each do |triggered|
            cancel_plan_id(triggered.execution_plan_id, reason)
            triggered.future.fail(reason)
          end
          @semaphores.delete(parent_id)
        end
      end

      private

      def cancel_plan_id(plan_id, reason)
        plan = @world.persistence.load_execution_plan(plan_id)
        steps = plan.run_steps
        steps.each do |step|
          step.state = :error
          step.error = ::Dynflow::ExecutionPlan::Steps::Error.new(reason)
          step.save
        end
        plan.update_state(:stopped)
        plan.save
      end

      def execute_triggered(triggered)
        @world.execute(triggered.execution_plan_id, triggered.finished)
      end

      def set_up_clock_for(plan_id, initial = false)
        if @semaphores[plan_id].children.key? :time
          timeout_message = 'The task could not be started within the maintenance window.'
          interval = @semaphores[plan_id].children[:time].meta[:interval]
          timeout = @semaphores[plan_id].children[:time].meta[:time_span]
          @world.clock.ping(self, interval, [:release, plan_id, :time])
          @world.clock.ping(self, timeout, [:cancel, plan_id, timeout_message]) if initial
        end
      end

      def create_semaphores(hash)
        semaphores = hash.keys.reduce(Utils.indifferent_hash({})) do |acc, key|
          acc.merge(key => ::Dynflow::Semaphores::Stateful.new_from_hash(hash[key]))
        end
        ::Dynflow::Semaphores::Aggregating.new(semaphores)
      end
    end
  end
end
