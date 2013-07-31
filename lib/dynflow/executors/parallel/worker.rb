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
                Work.(~any) --> step { run_step(step) }
        end

        def run_step(step)
          step.execute
          @pool << WorkerDone[step: step, worker: self]
        end
      end
    end
  end
end
