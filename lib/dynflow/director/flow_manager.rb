# frozen_string_literal: true
module Dynflow
  class Director
    class FlowManager
      include Algebrick::TypeCheck

      attr_reader :execution_plan

      def initialize(execution_plan, flow)
        @execution_plan = Type! execution_plan, ExecutionPlan
        @dependency_tree = Utils::LeafTree.new
        flow_to_dependency_hash(flow)
      end

      def done?
        @dependency_tree.empty?
      end

      def what_is_next(flow_step)
        return [] if flow_step.state == :suspended
        # TODO: What was this for again?
        # success = flow_step.state != :error
        @dependency_tree.pluck(flow_step.id)
        leaves = @dependency_tree.leaves
        puts "STEP: #{flow_step.id}: #{flow_step.state} - #{leaves} - #{@dependency_tree}"
        leaves.each { |leaf| @dependency_tree.add(leaf, leaf) }

        steps leaves
      end

      def start
        ids = @dependency_tree.leaves
        ids.each { |leaf| @dependency_tree.add(leaf, leaf) }
        raise 'invalid state' if ids.empty? && !done?
        steps ids
      end

      def steps(ids)
        ids.map { |id| execution_plan.steps[id] }
      end

      private

      def flow_to_dependency_hash(flow, parent_ids = [])
        case flow
        when Flows::Atom
          @dependency_tree.add(flow.step_id, parent_ids)
          [flow.step_id]
        when Flows::Sequence
          flow.flows.reduce(parent_ids) do |parent_ids, subflow|
            flow_to_dependency_hash(subflow, parent_ids)
          end
        when Flows::Concurrence
          flow.flows.map do |subflow|
            flow_to_dependency_hash(subflow, parent_ids)
          end
        end
      end
    end
  end
end
