module Dynflow
  module Serialization
    class SimpleSerializationDriver

      def serialize_run_plan(run_plan)
        out = {}
        out['step_type'] = run_plan.class.name
        if run_plan.is_a? Dynflow::Step
          out['persistence_id'] = run_plan.persistence.id
        else
          out['steps'] = run_plan.steps.map { |step| serialize_run_plan(step) }
        end
        return out
      end

      def restore_run_plan(serialized_run_plan)
        step_type = serialized_run_plan['step_type'].constantize
        if step_type.ancestors.include?(Dynflow::Step)
          return persisted_step(serialized_run_plan['persistence_id'])
        else
          steps = serialized_run_plan['steps'].map do |serialized_step|
            restore_run_plan(serialized_step)
          end
          return step_type.new(steps)
        end
      end

    end
  end
end