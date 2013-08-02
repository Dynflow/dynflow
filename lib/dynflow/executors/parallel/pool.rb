module Dynflow
  module Executors
    class Parallel < Abstract
      class Pool < MicroActor
        class RoundRobin
          def initialize
            @data   = []
            @cursor = 0
          end

          def add(item)
            @data.push item
            self
          end

          def delete(item)
            @data.delete item
            self
          end

          def next
            @cursor = 0 if @cursor > @data.size-1
            @data[@cursor].tap { @cursor += 1 }
          end

          def empty?
            @data.empty?
          end
        end

        class JobStorage
          def initialize
            @round_robin = RoundRobin.new
            @jobs        = Hash.new { |h, k| h[k] = [] }
          end

          def add(step)
            @round_robin.add step.execution_plan_id unless tracked?(step)
            @jobs[step.execution_plan_id] << step
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

          def tracked?(step)
            @jobs.has_key? step.execution_plan_id
          end

          def delete(execution_plan_id)
            @round_robin.delete execution_plan_id
            @jobs.delete execution_plan_id
          end
        end

        def initialize(manager, pool_size)
          super()
          @manager      = manager
          @free_workers = Array.new(pool_size) { Worker.new(self) }
          @jobs         = JobStorage.new
        end

        private

        def on_message(message)
          match message,
                Work.(~any) --> step do
                  @jobs.add step
                  distribute_jobs
                end,
                WorkerDone.(~any, ~any) --> step, worker do
                  @manager << PoolDone[step]
                  @free_workers << worker
                  distribute_jobs
                end
        end

        def distribute_jobs
          @free_workers.pop << Work[@jobs.pop] until @free_workers.empty? || @jobs.empty?
        end
      end
    end
  end
end
