module Dynflow
  module Executors
    class Parallel < Abstract
      class Pool < MicroActor
        def initialize(manager, pool_size)
          super()
          @manager      = manager
          @free_workers = Array.new(pool_size) { Worker.new(self) }
          @jobs         = []
        end

        private

        def on_message(message)
          match message,
                Work.(~any) --> step do
                  @jobs << step
                  distribute_jobs
                end,
                WorkerDone.(~any, ~any) --> step, worker do
                  @manager << PoolDone[step]
                  @free_workers << worker
                  distribute_jobs
                end
        end

        def distribute_jobs
          @free_workers.pop << Work[@jobs.shift] until @free_workers.empty? || @jobs.empty?
        end
      end
    end
  end
end
