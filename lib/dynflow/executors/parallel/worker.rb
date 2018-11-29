module Dynflow
  module Executors
    class Parallel < Abstract
      class Worker < Actor
        def initialize(pool, transaction_adapter, telemetry_options = {})
          @pool                = Type! pool, Concurrent::Actor::Reference
          @transaction_adapter = Type! transaction_adapter, TransactionAdapters::Abstract
          @telemetry_options   = telemetry_options
        end

        def on_message(work_item)
          ok = false
          Executors.run_user_code do
            work_item.execute
            ok = true
          end
        rescue Errors::PersistenceError => e
          @pool.tell([:handle_persistence_error, reference, e, work_item])
          ok = false
        ensure
          Dynflow::Telemetry.with_instance { |t| t.increment_counter(:dynflow_worker_events, 1, @telemetry_options) }
          @pool.tell([:worker_done, reference, work_item]) if ok
        end
      end
    end
  end
end
