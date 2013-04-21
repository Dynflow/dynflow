require 'active_support/inflector'
require 'forwardable'
module Eventum
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
      @logger ||= Eventum::Logger.new(self.class)
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

    class RuoteBus < Bus

      class ProcessDsl

        def initialize(&block)
          @steps = []
          instance_eval(&block)
        end

        def run_action(action, input)
          @steps << ['participant',
                     {'ref' => action.name, 'input' => input},
                     []]
        end

        def finalize
          @steps << ['participant', {'ref' => 'finalize'}, []]
        end

        def _definition
          return @_definition if @definition
          @_definition = ['define', {}, [['cursor', {}, @steps]]]
        end

      end

      attr_reader :board

      def initialize
        require 'ruote'
        super
        @board = Ruote::Dashboard.new(Ruote::Worker.new(Ruote::HashStorage.new))
        @board.register 'finalize' do |workitem|
          outputs = workitem['outputs'].map { |m| Eventum::Message.decode(m) }
          Eventum::Bus.finalize(outputs)
          reply
        end

        Action.actions.each do |action_class|
          @board.register action_class.name do |workitem|
            action_class = workitem['params']['ref'].constantize
            action = Eventum::Bus.process(action_class, workitem.fields['params']['input'])
            workitem.fields['outputs'] << action.encode
            reply
          end
        end

      end

      def trigger(execution_plan)
        definition = construct_definition(execution_plan)
        @board.launch(definition,
                      'outputs' => [])
      end

      def construct_definition(execution_plan)
        dsl = ProcessDsl.new do
          execution_plan.each do |action_class, subinput|
            run_action(action_class, subinput)
          end
        end
        dsl.finalize
        definition = dsl._definition
        return definition
      end

      def wait_for(wfid)
        result = @board.wait_for(wfid)
        if error = result["error"]
          exception_class = error["class"].constantize
          exception = exception_class.new(error["message"])
          exception.set_backtrace(error["trace"])
          raise exception
        end
        return result
      end

    end

  end
end
