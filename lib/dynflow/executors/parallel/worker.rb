module Dynflow
  module Executors
    class Parallel < Abstract
      class Worker < Concurrent::Actor::Context
        include Algebrick::Matching

        def initialize(pool, transaction_adapter)
          @pool                = Type! pool, Concurrent::Actor::Reference
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
          @pool << WorkerDone[work: message, worker: reference]
        ensure
          @transaction_adapter.cleanup
        end
      end
    end
  end
end
