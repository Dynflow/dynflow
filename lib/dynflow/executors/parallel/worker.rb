module Dynflow
  module Executors
    class Parallel < Abstract
      class Worker < MicroActor
        def initialize(pool, transaction_adapter)
          super(pool.logger, pool, transaction_adapter)
        end

        private

        def delayed_initialize(pool, transaction_adapter)
          @pool                = pool
          @transaction_adapter = Type! transaction_adapter, TransactionAdapters::Abstract
        end

        def on_message(message)
          match message,
                Work::Step.(step: ~any) | Work::Event.(step: ~any, event: Event.(event: ~any)) >-> step, event do
                  step.execute event
                end,
                Work::Finalize.(~any, any) >-> sequential_manager do
                  sequential_manager.finalize
                end
          @pool << WorkerDone[work: message, worker: self]
          @transaction_adapter.cleanup
        end
      end
    end
  end
end
