module Dynflow
  module Exporters
    class HTML < Abstract

      def export_execution_plan(plan = @execution_plan)
        erb :export,
            :locals => {
              :template => :show,
              :plan => plan
            }
      end

      def export_index(plans = @execution_plan)
        plans ||= find_execution_plans(true, false)
        erb :export,
            :locals => {
              :template => :index,
              :plans => plans
            }
      end

      def export_all_plans(plans = @execution_plan)
        plans.map { |plan| export_execution_plan(plan) }
      end

      def export
        export_execution_plan
      end

      private

      def erb(*args)
        @options[:console].erb(*args)
      end
    end
  end
end
