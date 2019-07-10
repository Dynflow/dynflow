module Dynflow
  module Executors
    class Parallel
      class Pool < Actor
        class JobStorage
          def initialize
            @jobs = []
          end

          def add(work)
            @jobs << work
          end

          def pop
            @jobs.shift
          end

          def queue_size
            execution_status.values.reduce(0, :+)
          end

          def empty?
            @jobs.empty?
          end

          def queue_size(execution_plan_id = nil)
            if execution_plan_id
              @jobs.count do |item|
                item.respond_to?(:execution_plan_id) && item.execution_plan_id == execution_plan_id
              end
            else
              @jobs.size
            end
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
            :queue_size => @jobs.queue_size(execution_plan_id) }
        end

        private

        def try_to_terminate
          if terminating?
            @free_workers.map { |worker| worker.ask(:terminate!) }.map(&:wait)
            @pool_size -= @free_workers.count
            @free_workers = []
            if @pool_size.zero?
              @executor_core.tell([:finish_termination, @name])
              finish_termination
            end
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
