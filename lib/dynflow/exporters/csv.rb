module Dynflow
  module Exporters
    class CSV < Abstract

      WANTED_ATTRIBUTES = ['id', 'state', 'type', 'label', 'result', 'parent_task_id', 'started_at', 'ended_at']

      def export(plan)
        plan.to_hash.select { |key, _| WANTED_ATTRIBUTES.include? key }.join(',')
      end

      def result
        header = [WANTED_ATTRIBUTES.join(',')]
        @result = (header + super).join("\n")
      end

    end
  end
end
