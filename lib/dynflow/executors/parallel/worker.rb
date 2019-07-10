module Dynflow
  module Executors
    class Parallel
      class Worker < Actor
        def initialize(pool, transaction_adapter, telemetry_options = {})
          @pool                = Type! pool, Concurrent::Actor::Reference
          @transaction_adapter = Type! transaction_adapter, TransactionAdapters::Abstract
          @telemetry_options   = telemetry_options
        end

        def on_message(work_item)
          already_responded = false
          Executors.run_user_code do
            work_item.execute
          end
        rescue Errors::PersistenceError => e
          @pool.tell([:handle_persistence_error, reference, e, work_item])
          already_responded = true
        ensure
          Dynflow::Telemetry.with_instance { |t| t.increment_counter(:dynflow_worker_events, 1, @telemetry_options) }
          if !already_responded && Concurrent.global_io_executor.running?
            @pool.tell([:worker_done, reference, work_item])
          end
        end
      end
    end
  end
end
