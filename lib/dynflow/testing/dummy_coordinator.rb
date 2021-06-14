# frozen_string_literal: true
module Dynflow
  module Testing
    class DummyCoordinator
      def find_records(*args)
        []
      end
    end
  end
end
