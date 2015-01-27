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
                (on Work::Step.(step: ~any) |
                        Work::Event.(step: ~any, event: Parallel::Event.(event: ~any)) do |step, event|
                  step.execute event
                end),
                (on Work::Finalize.(~any, any) do |sequential_manager|
                  sequential_manager.finalize
                 end)
        rescue Errors::PersistenceError => e
          @pool << e
        ensure
          @pool << WorkerDone[work: message, worker: self]
          @transaction_adapter.cleanup
        end
      end
    end
  end
end
