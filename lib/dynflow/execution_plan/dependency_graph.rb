module Dynflow
  class ExecutionPlan::DependencyGraph

    def initialize
      @graph = Hash.new { |h, k| h[k] = Set.new }
    end

    # adds dependencies to graph that +step+ has based
    # on the steps referenced in its +input+
    def add_dependencies(step, input)
      required_step_ids = extract_required_step_ids(input)
      required_step_ids.each do |required_step_id|
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

    private

    # @return [Array<Fixnum>] - ids of steps referenced from args
    def extract_required_step_ids(value)
      ret = case value
            when Hash
              value.values.map { |val| extract_required_step_ids(val) }
            when Array
              value.map { |val| extract_required_step_ids(val) }
            when ExecutionPlan::OutputReference
              value.step_id
            else
              # no reference hidden in this arg
            end
      return Array(ret).flatten.compact
    end


  end
end
