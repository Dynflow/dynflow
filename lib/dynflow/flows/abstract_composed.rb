module Dynflow
  module Flows
    class AbstractComposed < Abstract

      attr_reader :flows

      def initialize(flows)
        is_kind_of! flows, Array
        flows.all? { |f| is_kind_of! f, Abstract }
        @flows = flows
      end

      def to_hash
        super.merge(:flows => flows.map(&:to_hash))
      end

      def <<(v)
        @flows << v
        self
      end

      def [](*args)
        @flows[*args]
      end

      def []=(*args)
        @flows.[]=(*args)
      end

      def size
        @flows.size
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

      def self.new_from_hash(hash, execution_plan)
        check_class_matching hash
        new hash[:flows].map { |flow_hash| from_hash(flow_hash, execution_plan) }
      end

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

        return satisfying_flows.to_a
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
  end
end
