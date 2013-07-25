require 'forwardable'

module Dynflow
  module Flows

    class Abstract

      def empty?
        self.size == 0
      end

      def size
        raise NotImplementedError
      end

      def includes_step?(step_id)
        self.all_steps.any? { |step| step.id == step_id }
      end

      def all_steps
        raise NotImplementedError
      end

      def flatten!
        raise NotImplementedError
      end

    end

    class Empty < Abstract
    end

    class Atom < Abstract

      attr_reader :step

      def initialize(step)
        @step = step
      end

      def size
        1
      end

      def all_steps
        [step]
      end

      def flatten!
        # nothing to do
      end
    end

    class AbstractComposed < Abstract

      attr_reader :flows

      extend Forwardable

      def_delegators :@flows, :<<, :[], :[]=, :size

      def initialize(flows)
        @flows = flows
      end

      alias_method :sub_flows, :flows

      # @return [Array<Step>] all steps recursively in the flow
      def all_steps
        flows.map(&:all_steps).flatten
      end

      def add_and_resolve(dependency_graph, new_flow)
        return if new_flow.empty?

        satisfying_flows = find_satisfying_sub_flows(dependency_graph, new_flow)
        add_to_sequence(satisfying_flows, new_flow)
        flatten!
      end

      def flatten!
        self.sub_flows.to_enum.with_index.reverse_each do |flow, i|
          if flow.class == self.class
            expand_steps(i)
          elsif flow.is_a?(AbstractComposed) && flow.sub_flows.size == 1
            self.sub_flows[i] = flow.sub_flows.first
          end
        end

        self.sub_flows.map(&:flatten!)
      end

      protected

      # adds the +new_flow+ in a way that it's in sequence with
      # the +satisfying_flows+
      def add_to_sequence(satisfying_flows, new_flow)
        raise NotImplementedError
      end

      private

      def find_satisfying_sub_flows(dependency_graph, new_flow)
        satisfying_flows = Set.new
        new_flow.all_steps.each do |step|
          dependency_graph.required_step_ids(step.id).each do |required_step_id|
            satisfying_flow = sub_flows.find do |flow|
              flow.includes_step?(required_step_id)
            end
            if satisfying_flow
              satisfying_flows << satisfying_flow
              dependency_graph.mark_satisfied(step.id, required_step_id)
            end
          end
        end

        return satisfying_flows
      end

      def expand_steps(index)
        expanded_step = self.sub_flows[index]
        self.sub_flows.delete_at(index)
        expanded_step.sub_flows.each do |flow|
          self.sub_flows.insert(index, flow)
          index += 1
        end
      end

    end

    class Concurrence < AbstractComposed

      protected

      def add_to_sequence(satisfying_flows, dependent_flow)
        if satisfying_flows.empty?
          self.sub_flows << dependent_flow
          return
        end
        extracted_flow   = extract_flows(satisfying_flows)
        sequence         = Sequence.new([extracted_flow])

        self.sub_flows << sequence
        sequence  << dependent_flow
      end

      def extract_flows(extracted_sub_flows)
        extracted_sub_flows.each do |sub_flow|
          self.sub_flows.delete(sub_flow)
        end

        return Concurrence.new(extracted_sub_flows)
      end

    end

    class Sequence < AbstractComposed

      protected

      def add_to_sequence(satisfying_flows, dependent_flow)
        # the flows are already in sequence, we don't need to do anything extra
        self << dependent_flow
      end

    end
  end
end
