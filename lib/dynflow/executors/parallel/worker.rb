module Dynflow
  module Executors
    class Parallel < Abstract
      class Worker < Actor
        def initialize(pool, transaction_adapter)
          @pool                = Type! pool, Concurrent::Actor::Reference
          @transaction_adapter = Type! transaction_adapter, TransactionAdapters::Abstract
        end

        def on_message(work_item)
          Executors.run_user_code do
            work_item.execute
          end
        rescue Errors::PersistenceError => e
          @pool.tell([:handle_persistence_error, e])
        ensure
          @pool.tell([:worker_done, reference, work_item])
        end
      end
    end
  end
end
