module Dynflow
  module Exporters
    class CSV < Abstract

      WANTED_ATTRIBUTES = %w(id state type label result parent_task_id started_at ended_at).map(&:to_sym)

      def export(plan)
        hash = plan.to_hash
        hash[:label] = plan.root_plan_step.action_class.name
        WANTED_ATTRIBUTES.map { |attr| hash[attr] }.join(',')
      end

      def result
        header = [WANTED_ATTRIBUTES.join(',')]
        @result = (header + super).join("\n")
      end

    end
  end
end
