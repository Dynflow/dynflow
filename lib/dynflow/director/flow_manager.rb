# frozen_string_literal: true

require 'set'

module Dynflow
  class Director
    class FlowManager
      include Algebrick::TypeCheck

      attr_reader :execution_plan

      def initialize(execution_plan, flow)
        @execution_plan = Type! execution_plan, ExecutionPlan
        @dependency_graph = Utils::DependencyGraph.new
        @error_steps = []
        flow_to_dependency_hash(flow)
      end

      def done?
        halted? || @dependency_graph.empty?
      end

      # The execution is halted if there are error steps
      #   and there are no unblocked_nodes currently being executed
      #   and all the unblocked_nodes are error steps
      def halted?
        !@error_steps.empty? && @dependency_graph.blocked_nodes.none? &&
          Set.new(@dependency_graph.unblocked_nodes) == Set.new(@error_steps)
      end

      def what_is_next(flow_step)
        return [] if flow_step.state == :suspended
        if flow_step.state == :error
          @dependency_graph.unblock flow_step.id
          @error_steps << flow_step.id
          return []
        end
        @dependency_graph.satisfy(flow_step.id)
        unblocked_nodes = @dependency_graph.unblocked_nodes - @error_steps
        # Make a node depend on itself, this way it won't be considered unblocked
        #   We need this to not execute a step multiple times
        unblocked_nodes.each { |node| @dependency_graph.block(node) }

        steps unblocked_nodes
      end

      def levels
        @dependency_graph.levels.each do |ids|
          yield steps(ids)
        end
      end

      def start
        ids = @dependency_graph.unblocked_nodes
        ids.each { |node| @dependency_graph.block(node) }
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
          @dependency_graph.add(flow.step_id, parent_ids)
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
