require 'active_support/inflector'
require 'forwardable'
module Dynflow
  class Bus

    class << self
      extend Forwardable

      def_delegators :impl, :wait_for, :process, :trigger, :finalize

      def impl
        @impl ||= Bus::MemoryBus.new
      end
      attr_writer :impl
    end

    def finalize(outputs)
      outputs.each do |action|
        if action.respond_to?(:finalize)
          action.finalize(outputs)
        end
      end
    end

    def process(action_class, input, output = nil)
      # TODO: here goes the message validation
      action = action_class.new(input, output)
      action.run if action.respond_to?(:run)
      return action
    end

    def wait_for(*args)
      raise NotImplementedError, 'Abstract method'
    end

    def logger
      @logger ||= Dynflow::Logger.new(self.class)
    end

    class MemoryBus < Bus

      def initialize
        super
      end

      def trigger(execution_plan)
        outputs = []
        execution_plan.each do |(action_class, input)|
          outputs << self.process(action_class, input)
        end
        self.finalize(outputs)
      end

    end
  end
end
