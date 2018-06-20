require 'dynflow/telemetry_adapters/abstract'
require 'dynflow/telemetry_adapters/dummy'

module Dynflow
  class Telemetry
    class << self
      attr_reader :instance
      def set_adapter(adapter)
        @instance = adapter
      end

      def with_instance(&block)
        @instance.with_instance &block
      end
    end
  end
end
