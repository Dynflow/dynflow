# frozen_string_literal: true

module Dynflow
  module LoggerAdapters
    class Delegator < Abstract
      attr_reader :action_logger, :dynflow_logger

      def initialize(action_logger, dynflow_logger, formatters = [Formatters::Exception])
        @action_logger  = apply_formatters action_logger, formatters
        @dynflow_logger = apply_formatters dynflow_logger, formatters
      end
    end
  end
end
