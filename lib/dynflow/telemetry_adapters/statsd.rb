module Dynflow
  module TelemetryAdapters
    class StatsD < Abstract
      def initialize(host = '127.0.0.1:8125')
        require 'statsd-instrument'

        @instances = {}
        @host = host
        ::StatsD.backend = ::StatsD::Instrument::Backends::UDPBackend.new(host, :statsd)
      end
      
      def add_counter(name, description, instance_labels)
        raise "Metric already registered: #{name}" if @instances[name]
        @instances[name] = instance_labels
      end

      def add_gauge(name, description, instance_labels)
        raise "Metric already registered: #{name}" if @instances[name]
        @instances[name] = instance_labels
      end

      def add_histogram(name, description, instance_labels, buckets = DEFAULT_BUCKETS)
        raise "Metric already registered: #{name}" if @instances[name]
        @instances[name] = instance_labels
      end

      def increment_counter(name, value, tags)
        ::StatsD.increment(name_tag_mapping(name, tags), value)
      end

      def set_gauge(name, value, tags)
        ::StatsD.gauge(name_tag_mapping(name, tags), value)
      end

      def observe_histogram(name, value, tags)
        ::StatsD.measure(name_tag_mapping(name, tags), value)
      end

      private

      def name_tag_mapping(name, tags)
        instances = @instances[name]
        return name if instances.nil? || instances.empty?
        (name.to_s + '.' + instances.map {|x| tags[x]}.compact.join('.')).tr('-:/ ', '____')
      end
    end
  end
end
