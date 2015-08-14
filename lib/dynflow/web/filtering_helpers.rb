module Dynflow
  module Web
    module FilteringHelpers
      def supported_filter?(filter_attr)
        world.persistence.adapter.filtering_by.any? do |attr|
          attr.to_s == filter_attr.to_s
        end
      end

      def filtering_options(show_all = false)
        return @filtering_options if @filtering_options

        if params[:filters]
          params[:filters].map do |key, value|
            unless supported_filter?(key)
              halt 400, "Unsupported ordering"
            end
          end

          filters = params[:filters]
        elsif supported_filter?('state')
          excluded_states = show_all ? [] : ['stopped']
          filters = { 'state' => ExecutionPlan.states.map(&:to_s) - excluded_states }
        else
          filters = {}
        end
        @filtering_options = Utils.indifferent_hash(filters: filters)
        return @filtering_options
      end

      def find_execution_plans_options(show_all = false)
        options = Utils.indifferent_hash({})
        options.merge!(filtering_options(show_all))
        options.merge!(pagination_options)
        options.merge!(ordering_options)
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
  end
end
