# frozen_string_literal: true
module Dynflow
  module Flows
    class Concurrence < AbstractComposed

      protected

      def add_to_sequence(satisfying_flows, dependent_flow)
        if satisfying_flows.empty?
          self.sub_flows << dependent_flow
          return
        end
        extracted_flow = extract_flows(satisfying_flows)
        sequence       = Sequence.new([extracted_flow])

        self.sub_flows << sequence
        sequence << dependent_flow
      end

      def extract_flows(extracted_sub_flows)
        extracted_sub_flows.each do |sub_flow|
          self.sub_flows.delete(sub_flow)
        end

        return Concurrence.new(extracted_sub_flows)
      end
    end
  end
end
