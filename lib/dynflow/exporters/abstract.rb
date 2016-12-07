module Dynflow
  module Exporters
    class Abstract

      attr_reader :index

      def self.export_execution_plan_id(world, execution_plan_id, options = {})
        self.new(world, options)
          .add_id(execution_plan_id)
          .finalize.index[execution_plan_id][:result]
      end

      def self.export_execution_plan(execution_plan, options = {})
        self.new(execution_plan.world, options)
          .add(execution_plan)
          .finalize.index[execution_plan.id][:result]
      end

      # Expected workflow:
      # Exporter.new.add(foo).add(bar).add(baz).finalize.result
      def initialize(world = nil, options = {})
        @world   = world
        @options = options
        @index   = {}
      end

      # Add the execution_plan to the index, thus queueing it for exporting
      def add(execution_plan)
        @index[execution_plan.id] = {
          :plan   => execution_plan,
          :result => nil
        }
        self
      end

      # Add provided id to the index
      # The id will be resolved to the execution plan
      # in the #resolve_ids method along with all the other
      # index entries whose :plan is nil
      def add_id(execution_plan_id)
        @index[execution_plan_id] = {
          :plan   => nil,
          :result => nil
        }
        self
      end

      # The same as #add, but takes Array[ExecutionPlan]
      def add_many(execution_plans)
        execution_plans.each { |plan| add plan }
        self
      end

      # The same as #add_id, but takes Array[String]
      def add_many_ids(execution_plan_ids)
        execution_plan_ids.each { |plan_id| add_id plan_id }
        self
      end

      # Processes the entries in index and freezes the index and all entries
      def finalize
        return self if @index.frozen?
        resolve_ids
        @index.each do |key, value|
          @index[key].update(:result => export(value[:plan]))
          @index[key].freeze
        end
        @index.freeze
        self
      end

      # Generally put all the entries' results into an array
      def result
        return @result if @result
        finalize # In case someone forgot to finalize
        @result = @index.map { |_key, value| value[:result] }
      end

      # Export index of all entries
      def export_index
        @index.keys
      end

      private

      # Implement this method in sub-classes to provide the real exporting functionality
      # Transforms an execution plan to its exported representation
      def export(plan)
        raise NotImplementedError
      end

      # Selects all the entries from the index whose :plan is nil
      # Loads execution plans for those ids from the database
      def resolve_ids
        ids = @index.select { |_key, value| value[:plan].nil? }.keys
        return if ids.empty?
        @world.persistence.find_execution_plans(:filters => { :uuid => ids }).each do |plan|
          @index[plan.id].update(:plan => plan)
        end
      end

    end
  end
end
