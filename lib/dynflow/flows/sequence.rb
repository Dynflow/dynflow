# frozen_string_literal: true
module Dynflow
  module Flows
    class Sequence < AbstractComposed

      protected

      def add_to_sequence(satisfying_flows, dependent_flow)
        # the flows are already in sequence, we don't need to do anything extra
        self << dependent_flow
      end
    end
  end
end
