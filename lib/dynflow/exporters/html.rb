module Dynflow
  module Exporters
    class HTML < Abstract

      def export_execution_plan(plan)
        erb :export,
            :locals => {
              :template => :show,
              :plan => plan
            }
      end

      def export_index
        plans = @index.values.map { |val| val[:plan] }
        erb :export,
            :locals => {
              :template => :index,
              :plans => plans
            }
      end

      def export(plan)
        export_execution_plan(plan)
      end

      private

      def erb(*args)
        @options[:console].erb(*args)
      end
    end
  end
end
