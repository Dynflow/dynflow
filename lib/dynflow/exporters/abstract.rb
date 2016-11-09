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
      # Exporter.new.add(foo).add(bar).add(baz).finalize
      def initialize(world = nil, options = {})
        @world   = world
        @options = options
        @index   = {}
      end

      # Add execution plan to export
      def add(execution_plan)
        @index[execution_plan.id] = {
          :plan   => execution_plan,
          :result => nil
        }
        self
      end

      # Add execution plan to export by id
      def add_id(execution_plan_id)
        @index[execution_plan_id] = {
          :plan   => nil,
          :result => nil
        }
        self
      end

      def add_many(execution_plans)
        execution_plans.each { |plan| add plan }
        self
      end

      def add_many_ids(execution_plan_ids)
        execution_plan_ids.each { |plan_id| add_id plan_id }
        self
      end

      # Processes the entries in index, generate result
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

      def export(plan)
        raise NotImplementedError
      end

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
