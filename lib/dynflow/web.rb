require 'dynflow'
require 'pp'
require 'sinatra'
require 'yaml'

module Dynflow
  module Web

    def self.setup(&block)
      old_console = Sinatra.new(Web::LegacyConsole) { instance_exec(&block)}
      Rack::Builder.app do
        run Rack::URLMap.new('/'        => old_console)
      end
    end

    def self.web_dir(sub_dir)
      web_dir = File.join(File.expand_path('../../../web', __FILE__))
      File.join(web_dir, sub_dir)
    end

    # TODO: find better place for this code
    module FilteringHelpers
      def supported_filter?(filter_attr)
        world.persistence.adapter.filtering_by.any? do |attr|
          attr.to_s == filter_attr.to_s
        end
      end

      def filtering_options
        return @filtering_options if @filtering_options

        if params[:filters]
          params[:filters].map do |key, value|
            unless supported_filter?(key)
              halt 400, "Unsupported ordering"
            end
          end

          filters = params[:filters]
        elsif supported_filter?('state')
          filters = { 'state' => ExecutionPlan.states.map(&:to_s) - ['stopped'] }
        else
          filters = {}
        end
        @filtering_options = { filters: filters }.with_indifferent_access
        return @filtering_options
      end

      def paginate?
        world.persistence.adapter.pagination?
      end

      def page
        (params[:page] || 0).to_i
      end

      def per_page
        (params[:per_page] || 10).to_i
      end

      def pagination_options
        if paginate?
          { page: page, per_page: per_page }
        else
          if params[:page] || params[:per_page]
            halt 400, "The persistence doesn't support pagination"
          end
          return {}
        end
      end

      def supported_ordering?(ord_attr)
        world.persistence.adapter.ordering_by.any? do |attr|
          attr.to_s == ord_attr.to_s
        end
      end

      def ordering_options
        return @ordering_options if @ordering_options

        if params[:order_by]
          unless supported_ordering?(params[:order_by])
            halt 400, "Unsupported ordering"
          end
          @ordering_options = { order_by: params[:order_by],
                                desc:     (params[:desc] == 'true') }
        elsif supported_ordering?('started_at')
          @ordering_options = { order_by: 'started_at', desc: true }
        else
          @ordering_options = {}
        end
        return @ordering_options
      end
    end

    module WorldHelpers
      def world
        settings.world
      end
    end

    require 'dynflow/web/legacy_console'
  end
end
