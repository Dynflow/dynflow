module Dynflow
  module Executors
    class Parallel < Abstract
      class Pool < Actor
        class JobStorage
          def initialize
            @round_robin = RoundRobin.new
            @jobs        = Hash.new { |h, k| h[k] = [] }
          end

          def add(work)
            @round_robin.add work.execution_plan_id unless tracked?(work)
            @jobs[work.execution_plan_id] << work
          end

          def pop
            return nil if empty?
            execution_plan_id = @round_robin.next
            @jobs[execution_plan_id].shift.tap { delete execution_plan_id if @jobs[execution_plan_id].empty? }
          end

          def queue_size
            execution_status.values.reduce(0, :+)
          end

          def empty?
            @jobs.empty?
          end

          def execution_status(execution_plan_id = nil)
            source = if execution_plan_id.nil?
                       @jobs
                     else
                       { execution_plan_id => @jobs.fetch(execution_plan_id, []) }
                     end
            source.reduce({}) do |acc, (plan_id, work_items)|
              acc.update(plan_id => work_items.count)
            end
          end

          private

          def tracked?(work)
            @jobs.has_key? work.execution_plan_id
          end

          def delete(execution_plan_id)
            @round_robin.delete execution_plan_id
            @jobs.delete execution_plan_id
          end
        end

        def initialize(world, core, name, pool_size, transaction_adapter)
          @world = world
          @name = name
          @executor_core = core
          @pool_size     = pool_size
          @jobs          = JobStorage.new
          @free_workers  = Array.new(pool_size) do |i|
            name = "worker-#{i}"
            Worker.spawn(name, reference, transaction_adapter, telemetry_options.merge(:worker => name))
          end
        end

        def schedule_work(work)
          @jobs.add work
          distribute_jobs
          update_telemetry
        end

        def worker_done(worker, work)
          @executor_core.tell([:work_finished, work])
          @free_workers << worker
          Dynflow::Telemetry.with_instance { |t| t.set_gauge(:dynflow_active_workers, -1, telemetry_options) }
          distribute_jobs
        end

        def handle_persistence_error(worker, error, work = nil)
          @executor_core.tell([:handle_persistence_error, error, work])
          @free_workers << worker
          distribute_jobs
        end

        def start_termination(*args)
          super
          try_to_terminate
        end

        def execution_status(execution_plan_id = nil)
          { :pool_size => @pool_size,
            :free_workers => @free_workers.count,
            :execution_status => execution_status(execution_plan_id) }
        end

        private

        def try_to_terminate
          if terminating? && @free_workers.size == @pool_size
            @free_workers.map { |worker| worker.ask(:terminate!) }.map(&:wait)
            @executor_core.tell([:finish_termination, @name])
            finish_termination
          end
        end

        def distribute_jobs
          try_to_terminate
          until @free_workers.empty? || @jobs.empty?
            Dynflow::Telemetry.with_instance { |t| t.set_gauge(:dynflow_active_workers, '+1', telemetry_options) }
            @free_workers.pop << @jobs.pop
            update_telemetry
          end
        end

        def telemetry_options
          { :queue => @name.to_s, :world => @world.id }
        end

        def update_telemetry
          Dynflow::Telemetry.with_instance { |t| t.set_gauge(:dynflow_queue_size, @jobs.queue_size, telemetry_options) }
        end
      end
    end
  end
end
