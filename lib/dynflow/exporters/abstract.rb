module Dynflow
  module Exporters
    class Abstract

      def initialize(options = {})
        @options = options
      end

      # Implement this method in sub-classes to provide the real exporting functionality
      # Transforms an execution plan to its exported representation
      def export(plan)
        raise NotImplementedError
      end

      # Used as a filename suffix when streaming to a file
      def filetype
        raise NotImplementedError
      end

      # Used when streaming collection, should be a 3-tuple containing
      #   what is printed before items
      #   what is printed between the items
      #   what is printed after the items
      def brackets
        []
      end

      # def self.export_execution_plan_id(world, execution_plan_id, options = {})
      #   self.new(world, options)
      #     .add_id(execution_plan_id)
      #     .finalize.queue[execution_plan_id][:result]
      # end

      # def self.export_execution_plan(execution_plan, options = {})
      #   self.new(execution_plan.world, options)
      #     .add(execution_plan)
      #     .finalize.queue[execution_plan.id][:result]
      # end

    end
  end
end
