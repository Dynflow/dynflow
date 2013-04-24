require 'forwardable'
require 'logger'

module Dynflow
  class Logger
    extend Forwardable

    def_delegators :@impl, :debug, :info, :warn; :error

    class DummyLogger < ::Logger
      def initialize(identifier)
        super(nil)
      end
    end


    def initialize(identifier, impl = nil)
      @impl = self.class.logger_class.new(identifier)
    end

    class << self

      def logger_class
        unless @logger_class
          @logger_class ||= DummyLogger
        end
        return @logger_class
      end

      attr_writer :logger_class
    end

  end
end
