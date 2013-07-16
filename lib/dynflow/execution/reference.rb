module Dynflow
  class Reference
    attr_reader :step, :field

    def initialize(step, field)
      @step  = step
      @field = field.to_s
      unless %w[input output].include? @field
        raise "#{self.inspect}: Unexpected reference field. Only input and output allowed"
      end
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
end
