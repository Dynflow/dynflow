module Dynflow
  module Executors
    class Parallel < Abstract
      class Worker < MicroActor
        def initialize(pool)
          super()
          @pool = pool
        end

        private

        def on_message(message)
          match message,
                Step.(~any, any) --> step do
                  step.execute
                end,
                ResumedStep.(~any, any, ~any) --> step, resumption do
                  step.resume(resumption[:method], *resumption[:args])
                end,
                Finalize.(~any, any) --> sequential_manager do
                  sequential_manager.finalize
            end
            @pool << WorkerDone[work: message, worker: self]
        end

      end
    end
  end
end
