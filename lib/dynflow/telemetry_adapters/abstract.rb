module Dynflow
  module TelemetryAdapters
    class Abstract
      DEFAULT_BUCKETS = [10, 50, 200, 1000, 15_000].freeze

      def add_counter(name, description, instance_labels = [])
      end

      def add_gauge(name, description, instance_labels = [])
      end

      def add_histogram(name, description, instance_labels = [], buckets = DEFAULT_BUCKETS)
      end

      def increment_counter(name, value = 1, tags = {})
      end

      def set_gauge(name, value, tags = {})
      end

      def observe_histogram(name, value, tags = {})
      end

      def with_instance
        yield self if block_given?
      end

      def register_metrics!
        add_gauge(:dynflow_active_workers, 'The number of currently busy workers', [:queue, :world])
        add_counter(:dynflow_worker_events, 'The number of processed events', [:name, :worker])

        add_gauge(:dynflow_active_execution_plans, 'The number of active execution plans', [:label, :world, :state])
        add_counter(:dynflow_finished_execution_plans, 'The number of execution plans', [:label, :world, :result])

        # TODO: Configure buckets in a sane manner
        add_histogram(:dynflow_step_real_time, 'The real time spent executing a step', [:action, :phase])
        add_histogram(:dynflow_step_execution_time, 'The real time spent executing a step', [:action, :phase])
      end
    end
  end
end
