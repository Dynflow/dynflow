module Dynflow
  module Exporters
    class ExportManager

      def initialize(world, exporter, io, options = {})
        @world    = world
        @exporter = exporter
        @options  = options
        @io       = io
        @db_batch_size = options.fetch(:db_batch_size, 50)
        @queue    = {}
        @ids = @plans = []
        @wrap_before, @separator, @wrap_after = @exporter.brackets
      end

      def add(plans)
        plans = [plans] unless plans.kind_of? Array
        @ids, @plans = plans.partition { |plan| plan.is_a? String }
        self
      end

      # Stream all the entries into one file
      def export_collection
        @io.write(@wrap_before) unless @wrap_before.nil?
        each do |uuid, content, last|
          yield uuid if block_given?
          @io.write(content)
          @io.write(@separator) if @separator && !last
        end
        @io.write(@wrap_after) unless @wrap_after.nil?
      end

      private

      def each
        return enum_for(:each) unless block_given?

        @plans.each do |plan|
          yield [plan.id, @exporter.export(plan), @ids.empty? && plan.id == @plans.last.id]
        end

        @ids.each_slice(@db_batch_size) do |batch|
          resolve_ids(batch).each do |uuid, plan|
            yield [uuid, @exporter.export(plan), uuid == @ids.last]
          end
        end
      end

      # Loads execution plans with provided ids from the database
      # Returns as [String, ExecutionPlan]
      def resolve_ids(ids)
        @world.persistence.find_execution_plans(:filters => { :uuid => ids }).map do |plan|
          [plan.id, plan]
        end
      end
    end
  end
end
