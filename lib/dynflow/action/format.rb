# frozen_string_literal: true

module Dynflow
  # Input/output format validation logic calling
  # input_format/output_format with block acts as a setter for
  # specifying the format. Without a block it acts as a getter
  module Action::Format
    # we don't evaluate tbe block immediatelly, but postpone it till all the
    # action classes are loaded, because we can use them to reference output format
    def input_format(&block)
      case
      when block && !@input_format_block
        @input_format_block = block
      when !block && @input_format_block
        return @input_format ||= Apipie::Params::Description.define(&@input_format_block)
      when block && @input_format_block
        raise "The input_format has already been defined in #{self.class}"
      when !block && !@input_format_block
        if superclass.respond_to? :input_format
          superclass.input_format
        else
          raise "The input_format has not been defined yet in #{self.class}"
        end
      end
    end

    def output_format(&block)
      case
      when block && !@output_format_block
        @output_format_block = block
      when !block && @output_format_block
        return @output_format ||= Apipie::Params::Description.define(&@output_format_block)
      when block && @output_format_block
        raise "The output_format has already been defined in #{self.class}"
      when !block && !@output_format_block
        if superclass.respond_to? :output_format
          superclass.output_format
        else
          raise "The output_format has not been defined yet in #{self.class}"
        end
      end
    end
  end
end
