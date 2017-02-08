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

      def initialize(world)
        @world = world
        @renderer = TaskRenderer.new(world)
      end

      def export(plan)
        render :export,
               :locals => {
                 :template => :show,
                 :plan => plan
               }
      end

      def filetype
        'html'
      end

      def export_index(plans)
        render :export,
               :locals => {
                 :template => :index,
                 :plans => plans
               }
      end

      def export_worlds
        worlds = @world.coordinator.find_worlds
        worlds.find { |world| world.data['id'] == @world.id }.data['meta'].update('doing_export' => true)

        render :export,
               :locals => {
                 :template => :worlds,
                 :worlds => worlds,
                 :validation_results => @world.worlds_validity_check(false)
               }
      end

      private

      def render(*args)
        @renderer.render(*args)
      end

    end
  end
end
