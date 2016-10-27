require 'dynflow/web'
require 'tilt'

module Dynflow
  module Exporters

    class TaskRenderer
      include ::ERB::Util
      include ::Dynflow::Web::FilteringHelpers
      include ::Dynflow::Web::ConsoleHelpers

      attr_reader :world

      def initialize(world)
        @world = world
        @cache = {
          :layout => ::Tilt.new(template :layout)
        }
        @export = true
      end

      def render(template, options = {})
        @cache[:layout].render(self) do
          erb(template, options)
        end
      end

      private

      def erb(file, options = {})
        @cache[file] ||= ::Tilt.new(template file)
        @cache[file].render(self, options[:locals])
      end

      def template(filename)
        File.join(::Dynflow::Web::Console.views, filename.to_s + '.erb')
      end

      def uri(link, *rest)
        link
      end

      def params
        {}
      end
    end

    class HTML < Abstract

      def initialize(world, *args)
        super(world, *args)
        @renderer = TaskRenderer.new(world)
      end

      def export_execution_plan(plan)
        render :export,
               :locals => {
                 :template => :show,
                 :plan => plan
               }
      end

      def export_index
        render :export,
               :locals => {
                 :template => :index,
                 :plans => @index.values.map { |val| val[:plan] }
               }
      end

      def export_worlds
        @validation_results = @world.worlds_validity_check(false)
        worlds = @world.coordinator.find_worlds.reject { |world| world.id == @world.id }
        render :export,
               :locals => {
                 :template => :worlds,
                 :worlds => worlds
               }
      end

      def export(plan)
        export_execution_plan(plan)
      end

      private

      def render(*args)
        @renderer.render(*args)
      end

    end
  end
end
