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

          def empty?
            @jobs.empty?
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

        def initialize(core, pool_size, transaction_adapter)
          @executor_core = core
          @pool_size     = pool_size
          @free_workers  = Array.new(pool_size) { |i| Worker.spawn("worker-#{i}", reference, transaction_adapter) }
          @jobs          = JobStorage.new
        end

        def schedule_work(work)
          @jobs.add work
          distribute_jobs
        end

        def worker_done(worker, work)
          @executor_core.tell([:work_finished, work])
          @free_workers << worker
          distribute_jobs
        end

        def handle_persistence_error(error)
          @executor_core.tell(:handle_persistence_error, error)
        end

        def start_termination(*args)
          super
          try_to_terminate
        end

        private

        def try_to_terminate
          if terminating? && @free_workers.size == @pool_size
            @free_workers.map { |worker| worker.ask(:terminate!) }.map(&:wait)
            @executor_core.tell(:finish_termination)
            finish_termination
          end
        end

        def distribute_jobs
          try_to_terminate
          @free_workers.pop << @jobs.pop until @free_workers.empty? || @jobs.empty?
        end
      end
    end
  end
end
