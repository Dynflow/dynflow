# frozen_string_literal: true

module Dynflow
  module Action::Format
    def input_format(&block)
      # Format definitions are not validated
      # This method is kept for backward compatibility but does nothing
    end

    def output_format(&block)
      # Format definitions are not validated
      # This method is kept for backward compatibility but does nothing
    end
  end
end
