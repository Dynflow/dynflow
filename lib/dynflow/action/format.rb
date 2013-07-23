module Dynflow

  # Input/output format validation logic calling
  # input_format/output_format with block acts as a setter for
  # specifying the format. Without a block it acts as a getter
  module Action::Format

    def input_format(&block)
      case
      when block && !@input_format
        @input_format = Apipie::Params::Description.define(&block)
      when !block && @input_format
        return @input_format
      when block && @input_format
        raise "The input_format has already been defined"
      when !block && !@input_format
        raise "The input_format has not been defined yet"
      end
    end

    def output_format(&block)
      case
      when block && !@output_format
        @output_format = Apipie::Params::Description.define(&block)
      when !block && @output_format
        return @output_format
      when block && @output_format
        raise "The output_format has already been defined"
      when !block && !@output_format
        raise "The output_format has not been dfined yet"
      end
    end

  end
end

