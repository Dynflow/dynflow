module Dynflow
  class Step
    extend Forwardable

    def_delegators :@data, '[]', '[]='

    attr_accessor :status, :persistence
    attr_reader :data, :action_class

    def prepare
      persist_before_run
      output = {}
    end

    def run
      action.run
    end

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
      ret << "(#{input.inspect}"
      ret << " ~> #{output.inspect}" if status != 'pending'
      ret << " ! #{error['exception']}: #{error['message']}" if error && !error.empty?
      ret << ")"
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

      action_class = begin
                       data['action_class'].constantize
                     rescue NameError => e
                       Dynflow::Action::Unknown.new(data['action_class'])
                     end
      ret.instance_variable_set("@action_class", action_class)
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

    def satisfying_step(step)
      return self if self.equal?(step)
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

  end
end
