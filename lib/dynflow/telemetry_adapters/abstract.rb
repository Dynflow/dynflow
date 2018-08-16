module Dynflow
  module TelemetryAdapters
    class Abstract
      # Default buckets to use when defining a histogram
      DEFAULT_BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 20, 30, 60, 120, 300, 600, 1200].freeze

      # Configures a counter to be collected
      #
      # @param [String] name Name of the counter
      # @param [String] description Human-readable description of the counter
      # @param [Array<String>] instance_labels Labels which will be assigned to the collected data
      # @return [void]
      def add_counter(name, description, instance_labels = [])
      end

      # Configures a gauge to be collected
      #
      # @param [String] name Name of the gauge
      # @param [String] description Human-readable description of the gauge
      # @param [Array<String>] instance_labels Labels which will be assigned to the collected data
      # @return [void]
      def add_gauge(name, description, instance_labels = [])
      end

      # Configures a histogram to be collected
      #
      # @param [String] name Name of the histogram
      # @param [String] description Human-readable description of the histogram
      # @param [Array<String>] instance_labels Labels which will be assigned to the collected data
      # @param [Array<Integer>] buckest Buckets to fit the value into
      # @return [void]
      def add_histogram(name, description, instance_labels = [], buckets = DEFAULT_BUCKETS)
      end

      # Increments a counter
      #
      # @param [String,Symbol] name Name of the counter to increment
      # @param [Integer] value Step to increment by
      # @param [Hash{Symbol=>String}] tags Tags to apply to this record
      # @return [void]
      def increment_counter(name, value = 1, tags = {})
      end

      # Modifies a gauge
      #
      # @param [String,Symbol] name Name of the gauge to increment
      # @param [String,Integer] value Step to change by
      # @param [Hash{Symbol=>String}] tags Tags to apply to this record
      # @return [void]
      def set_gauge(name, value, tags = {})
      end

      # Records a histogram entry
      #
      # @param [String,Symbol] name Name of the histogram
      # @param [String,Integer] value Value to record
      # @param [Hash{Symbol=>String}] tags Tags to apply to this record
      # @return [void]
      def observe_histogram(name, value, tags = {})
      end

      # Passes self into the block and evaulates it
      #
      # @yieldparam [Abstract] adapter the current telemetry adapter
      # @return [void]
      def with_instance
        yield self if block_given?
      end

      def measure(name, tags = {})
        before = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        yield
      ensure
        after = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        duration = (after - before) * 1000 # In miliseconds
        observe_histogram(name, duration, tags)
      end
    end
  end
end
