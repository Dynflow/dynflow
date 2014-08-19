module Dynflow
  module Testing
    class DummyStep
      extend Mimic
      mimic! ExecutionPlan::Steps::Abstract

      attr_accessor :state, :error
      attr_reader :id

      def initialize
        @state = :pending
        @id    = Testing.get_id
      end

      def save
      end

      def run_always
        return true
      end
    end
  end
end
