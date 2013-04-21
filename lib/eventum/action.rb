module Eventum
  class Action < Message

    def self.inherited(child)
      self.actions << child
    end

    def self.actions
      @actions ||= []
    end

    def self.subscribe
      nil
    end

    def self.require
      nil
    end

    def initialize(input, output = {})
      output ||= {}
      super('input' => input, 'output' => output)
    end

    def input
      @data['input']
    end

    def output
      @data['output']
    end

    # the block contains the expression in Apipie::Params::DSL
    # describing the format of message
    def self.output_format(&block)
      if block
        @output_format_block = block
      else
        @output_format ||= Apipie::Params::Description.define(&@output_format_block)
      end
    end

    def run
      # here is where we prepare the result
    end

    def validate!
      self.clss.output_format.validate!(@data['output'])
    end

  end
end
