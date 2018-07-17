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

        def initialize(core, name, pool_size, transaction_adapter)
          @name = name
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
            :execution_status => @jobs.execution_status(execution_plan_id) }
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
          @free_workers.pop << @jobs.pop until @free_workers.empty? || @jobs.empty?
        end
      end
    end
  end
end
