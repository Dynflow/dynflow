module Dynflow
  class Step

    class Reference

      attr_reader :step, :field

      def initialize(step, field)
        unless %w[input output].include? field
          raise "Unexpected reference field: #{field}. Only input and output allowed"
        end
        @step  = step
        @field = field
      end

      def encode
        unless @step.persistence
          raise "Reference can't be serialized without persistence available"
        end

        {
          'dynflow_step_persistence_id' => @step.persistence.persistence_id,
          'field' => @field
        }
      end

      def self.decode(data)
        return nil unless data.is_a? Hash
        return nil unless data.has_key?('dynflow_step_persistence_id')
        persistence_id = data['dynflow_step_persistence_id']
        self.new(Dynflow::Bus.persisted_step(persistence_id), data['field'])
      end

      def dereference
        @step.send(@field)
      end

      def inspect
        "Reference(#{@step.inspect}/#{@field})"
      end

    end

    extend Forwardable

    def_delegators :@data, '[]', '[]='

    attr_accessor :status
    attr_reader :data, :action_class

    # persistent representation of the step
    attr_accessor :persistence

    def input
      @data['input']
    end

    def input=(input)
      @data['input'] = input
    end

    def output
      @data['output']
    end

    def output=(output)
      @data['output'] = output
    end

    def error
      @data['error']
    end

    def error=(error)
      @data['error'] = error
    end

    # get a fresh instance of action class for execution
    def action
      action_class.new(input, output)
    end

    def inspect
      ret = action_class.name
      ret << "/"
      ret << self.class.name.split('::').last
      ret << "##{persistence.persistence_id}" if persistence && persistence.persistence_id
      ret << ": #{input.inspect}"
      ret << " ~> #{output.inspect}" if status != 'pending'
      return ret
    end

    def catch_errors
      yield
      self.status = 'success'
      return true
    rescue Exception => e
      self.error = {
        "exception" => e.class.name,
        "message"   => e.message,
        "backtrace"   => e.backtrace
      }
      self.status = 'error'
      return false
    end

    def ==(other)
      self.encode == other.encode
    end

    def self.decode(data)
      ret = data['step_class'].constantize.allocate
      ret.instance_variable_set("@action_class", data['action_class'].constantize)
      ret.instance_variable_set("@status",       data['status'])
      ret.instance_variable_set("@data",         decode_data(data['data']))
      return ret
    end

    def encode
      {
        'step_class'   => self.class.name,
        'action_class' => action_class.name,
        'status'       => status,
        'data'         => encoded_data
      }
    end

    def self.decode_data(data)
      walk(data) do |item|
        Reference.decode(item)
      end
    end

    # we need this to encode the reference correctly
    def encoded_data
      self.class.walk(data) do |item|
        if item.is_a? Reference
          item.encode
        end
      end
    end

    def replace_references!
      @data = self.class.walk(data) do |item|
        if item.is_a? Reference
          if item.step.status == 'skipped' || item.step.status == 'error'
            self.status = 'skipped'
            item
          else
            item.dereference
          end
        end
      end
    end

    # walks hash depth-first, yielding on every value
    # if yield return non-false value, use that instead of original
    # value in a resulting hash
    def self.walk(data, &block)
      if converted = (yield data)
        return converted
      end
      case data
      when Array
        data.map { |d| walk(d, &block) }
      when Hash
        data.reduce({}) { |h, (k, v)| h.update(k => walk(v, &block)) }
      else
        data
      end
    end

    def persist
      if @persistence
        @persistence.persist(self)
      end
    end

    def persist_before_run
      if @persistence
        @persistence.before_run(self)
      end
    end

    def persist_after_run
      if @persistence
        @persistence.after_run(self)
      end
    end

    class Plan < Step

      def initialize(action)
        # we want to have the steps separated:
        # not using the original action object
        @action_class = action.class
        self.status = 'finished' # default status
        @data = {}.with_indifferent_access
      end

    end

    class Run < Step

      def initialize(action)
        # we want to have the steps separated:
        # not using the original action object
        @action_class = action.class
        self.status = 'pending' # default status
        @data = {
          'input'  => action.input,
          'output' => action.output
        }.with_indifferent_access
      end

    end

    class Finalize < Step

      def initialize(run_step)
        # we want to have the steps separated:
        # not using the original action object
        @action_class = run_step.action_class
        self.status = 'pending' # default status
        if run_step.action.respond_to? :run
          @data = {
            'input' => Reference.new(run_step, 'input'),
            'output' => Reference.new(run_step, 'output'),
          }
        else
          @data = run_step.data
        end
      end

    end
  end
end
