# frozen_string_literal: true

module Dynflow
  module TelemetryAdapters
    # Telemetry adapter which does not evaluate blocks passed to {#with_instance}.
    class Dummy < Abstract
      # Does nothing with the block passed to it
      #
      # @return void
      def with_instance
        # Do nothing
      end

      def measure(_name, _tags = {})
        # Just call the block
        yield
      end
    end
  end
end
