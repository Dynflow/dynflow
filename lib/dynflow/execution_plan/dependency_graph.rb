# frozen_string_literal: true
module Dynflow
  class ExecutionPlan::DependencyGraph

    def initialize
      @graph = Hash.new { |h, k| h[k] = Set.new }
    end

    # adds dependencies to graph that +step+ has based
    # on the steps referenced in its +input+
    def add_dependencies(step, action)
      action.required_step_ids.each do |required_step_id|
        @graph[step.id] << required_step_id
      end
    end

    def required_step_ids(step_id)
      @graph[step_id]
    end

    def mark_satisfied(step_id, required_step_id)
      @graph[step_id].delete(required_step_id)
    end

    def unresolved?
      @graph.any? { |step_id, required_step_ids| required_step_ids.any? }
    end

  end
end
