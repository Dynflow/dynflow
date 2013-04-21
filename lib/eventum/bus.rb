require 'active_support/inflector'
require 'forwardable'
module Eventum
  class Bus

    class << self
      extend Forwardable

      def_delegators :impl, :wait_for, :process, :trigger, :register_finalizer, :finalize

      def impl
        @impl ||= Bus::MemoryBus.new
      end
      attr_writer :impl
    end

    def initialize
      @finalizers = Hash.new { |h, k| h[k] = [] }
      @actions = Action.actions
    end

    def register_finalizer(workflow, finalizer = nil, &block)
      workflow = workflow.name if workflow.is_a? Class
      finalizer ||= block
      @finalizers[workflow] << finalizer
    end

    def finalize(event, outputs)
      @finalizers[event.class.name].map { |finalizer| finalizer.call(event, outputs) }
    end

    def process(action_class, input, output = nil)
      # TODO: here goes the message validation
      action = action_class.new(input, output)
      action.run
      return action
    end

    def wait_for(*args)
      raise NotImplementedError, 'Abstract method'
    end

    def actions_for_event(event)
      @actions.find_all do |action|
        case action.subscribe
        when Hash
          action.subscribe.keys.include?(event.class)
        when Array
          action.subscribe.include?(event.class)
        else
          action.subscribe == event.class
        end
      end
    end

    def ordered_actions_with_mapping(event)
      dep_tree = actions_for_event(event).reduce({}) do |h, action_class|
        h.update(action_class => action_class.require)
      end

      ordered_actions = []
      while (no_dep_actions = dep_tree.find_all { |part, require| require.nil? }).any? do
        no_dep_actions = no_dep_actions.map(&:first)
        ordered_actions.concat(no_dep_actions.sort_by(&:name))
        no_dep_actions.each { |part| dep_tree.delete(part) }
        dep_tree.keys.each do |part|
          dep_tree[part] = nil if ordered_actions.include?(dep_tree[part])
        end
      end

      if (unresolved = dep_tree.find_all { |_, require| require }).any?
        raise 'The following deps were unresolved #{unresolved.inspect}'
      end

      return ordered_actions.reduce({}) do |ret, action_class|
        if action_class.subscribe.is_a?(Hash)
          mapping = action_class.subscribe[event.class].to_s
        else
          mapping = nil
        end
        ret.update(action_class => mapping)
      end
    end

    def logger
      @logger ||= Eventum::Logger.new(self.class)
    end

    class MemoryBus < Bus

      def initialize
        super
      end

      def trigger(event)
        outputs = []
        self.ordered_actions_with_mapping(event).each do |action_class, mapping|
          if mapping
            next if event[mapping].nil?
            event[mapping].each do |subinput|
              outputs << self.process(action_class, subinput)
            end
          else
            outputs << self.process(action_class, event)
          end
        end
        self.finalize(event, outputs)
      end

    end

    class RuoteBus < Bus

      class ProcessDsl

        def initialize(&block)
          @steps = []
          instance_eval(&block)
        end

        def run_action(action, mapping)
          iterator = ['concurrence',
             {'merge_type' => 'union'},
             [['iterator',
               {'on_field' => "event.data.#{mapping}", 'to_v' => 'subinput'},
               [['participant', {'ref' => action.name, 'input' => '$v:subinput'}, []]]]
            ]]
          @steps << iterator
        end

        def finalize(event_class)
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
          event = Eventum::Message.decode(workitem['event'])
          outputs = workitem['outputs'].map { |m| Eventum::Message.decode(m) }
          Eventum::Bus.finalize(event, outputs)
          reply
        end

        @actions.each do |action_class|
          @board.register action_class.name do |workitem|
            action_class = workitem['params']['ref'].constantize
            action = Eventum::Bus.process(action_class, workitem.fields['params']['input'])
            workitem.fields['outputs'] << action.encode
            reply
          end
        end

      end

      def trigger(event)
        definition = construct_definition(event)
        @board.launch(definition,
                      'event' => event.encode,
                      'outputs' => [])
      end

      def construct_definition(event)
        ordered_actions_with_mapping = self.ordered_actions_with_mapping(event)
        dsl = ProcessDsl.new do
          ordered_actions_with_mapping.each do |action_class, mapping|
            run_action(action_class, mapping)
          end
        end
        dsl.finalize(event.class)
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
