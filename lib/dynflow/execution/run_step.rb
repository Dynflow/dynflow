module Dynflow
  class RunStep < Dynflow::Step

    def initialize(args)
      @action_class = args[:action_class]
      input = args[:input] || {}
      output = args[:output] || {}
      @data = {
        'input'  => input,
        'output' => output
      }
      self.status = 'pending' # default status
    end

    # Output references needed for this step to run
    # @return [Array<Reference>]
    def dependencies
      self.input.values.map do |value|
        if value.is_a?(Reference) && value.field.to_s == 'output'
          value
        elsif value.is_a? Array
          value.find_all { |val| val.is_a?(Reference) && val.field.to_s == 'output' }
        end
      end.compact.flatten.map(&:step)
    end

  end
end
