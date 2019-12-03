# frozen_string_literal: true

require 'set'

module Dynflow
  class Director
    class FlowManager
      include Algebrick::TypeCheck

      attr_reader :execution_plan

      def initialize(execution_plan, flow)
        @execution_plan = Type! execution_plan, ExecutionPlan
        @dependency_tree = Utils::LeafTree.new
        @error_steps = []
        flow_to_dependency_hash(flow)
      end

      def done?
        halted? || @dependency_tree.empty?
      end

      # The execution is halted if there are error steps
      #   and there are no leaves currently being executed
      #   and all the leaves are error steps
      def halted?
        !@error_steps.empty? && @dependency_tree.blocked_leaves.none? &&
          Set.new(@dependency_tree.leaves) == Set.new(@error_steps)
      end

      def what_is_next(flow_step)
        return [] if flow_step.state == :suspended
        if flow_step.state == :error
          @dependency_tree.unblock flow_step.id
          @error_steps << flow_step.id
          return []
        end
        @dependency_tree.pluck(flow_step.id)
        leaves = @dependency_tree.leaves - @error_steps
        # Make a leaf depend on itself, this way it won't be considered a leaf.
        #   We need this to not execute a step multiple times
        leaves.each { |leaf| @dependency_tree.block(leaf) }

        steps leaves
      end

      def start
        ids = @dependency_tree.leaves
        ids.each { |leaf| @dependency_tree.block(leaf) }
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
