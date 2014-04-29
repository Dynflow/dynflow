module Dynflow
  module Exporters
    class Abstract

      def self.export_execution_plan_id(world, execution_plan_id, options = {})
        execution_plan = world.persistence.load_execution_plan(execution_plan_id)
        self.export_execution_plan(execution_plan, options)
      end

      def self.export_execution_plan(execution_plan, options = {})
        self.new(execution_plan, options).export
      end

      def initialize(execution_plan, options = {})
        @execution_plan = execution_plan
        @options = options
      end

      def export
        raise NotImplementedError
      end
    end
  end
end
