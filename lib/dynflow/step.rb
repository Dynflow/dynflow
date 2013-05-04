module Dynflow
  class Step

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
      self.action_class.new(input, output)
    end

    def catch_errors
      yield
      self.status = 'success'
      return true
    rescue Exception => e
      self.error = {
        "exception" => e.class.name,
        "message"   => e.message
      }
      self.status = 'error'
      return false
    end

    def ==(other)
      self.encode == other.encode
    end

    def self.decode(data)
      ret = data['step_class'].constantize.allocate
      ret.instance_variable_set("@action_class", data['action_class'])
      ret.instance_variable_set("@status",       data['status'])
      ret.instance_variable_set("@data",         data['data'])
      return ret
    end

    def encode
      {
        'step_class'   => self.class.name,
        'action_class' => action_class.name,
        'status'       => status,
        'data'         => data
      }
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
        @data = run_step.data
      end

    end
  end
end
