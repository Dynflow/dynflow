module Dynflow
  module LoggerAdapters
    class Delegator < Abstract

      attr_reader :action_logger, :dynflow_logger

      def initialize(action_logger, dynflow_logger)
        @action_logger  = action_logger
        @dynflow_logger = dynflow_logger
      end
    end
  end
end
