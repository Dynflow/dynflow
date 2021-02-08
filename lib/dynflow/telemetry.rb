# frozen_string_literal: true
module Dynflow
  class Telemetry
    class << self
      attr_reader :instance

      # Configures the adapter to use for telemetry
      #
      # @param [TelemetryAdapters::Abstract] adapter the adapter to use
      def set_adapter(adapter)
        @instance = adapter
      end

      # Passes the block into the current telemetry adapter's
      # {TelemetryAdapters::Abstract#with_instance} method
      def with_instance(&block)
        @instance.with_instance &block
      end

      def measure(name, tags = {}, &block)
        @instance.measure name, tags, &block
      end

      # Registers the metrics to be collected
      # @return [void]
      def register_metrics!
        return if @registered
        @registered = true
        with_instance do |t|
          # Worker related
          t.add_gauge   :dynflow_active_workers, 'The number of currently busy workers',
                        [:queue, :world]
          t.add_counter :dynflow_worker_events, 'The number of processed events',
                        [:queue, :world, :worker]

          # Execution plan related
          t.add_gauge   :dynflow_active_execution_plans, 'The number of active execution plans',
                        [:action, :world, :state]
          t.add_gauge   :dynflow_queue_size, 'Number of items in queue',
                        [:queue, :world]
          t.add_counter :dynflow_finished_execution_plans, 'The number of execution plans',
                        [:action, :world, :result]

          # Step related
          # TODO: Configure buckets in a sane manner
          t.add_histogram :dynflow_step_real_time, 'The time between the start end end of the step',
                          [:action, :phase]
          t.add_histogram :dynflow_step_execution_time, 'The time spent executing a step',
                          [:action, :phase]

          # Connector related
          t.add_counter :dynflow_connector_envelopes, 'The number of envelopes handled by a connector',
                        [:world, :direction]

          # Persistence related
          t.add_histogram :dynflow_persistence, 'The time spent communicating with the database',
                          [:world, :method]
        end
      end
    end
  end
end
