module Dynflow
  module Executors
    class Parallel < Abstract
      class Worker < MicroActor
        def initialize(pool)
          super(pool.logger)
          @pool = pool
        end

        private

        def on_message(message)
          match message,
                Step.(~any, any) >-> step do
                  step.execute
                end,
                ProgressUpdateStep.(~any, any, ~any) >-> step, progress_update do
                  step.execute(progress_update.done, *progress_update.args)
                end,
                Finalize.(~any, any) >-> sequential_manager do
                  sequential_manager.finalize
                end,
                Terminate.(~any) >-> future do
                  terminate! future
                end
          @pool << WorkerDone[work: message, worker: self]
        end

        def terminate!(future)
          future.set true
          super()
        end

      end
    end
  end
end
