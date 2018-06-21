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
    end
  end
end
