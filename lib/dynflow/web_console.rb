require 'dynflow'
require 'pp'
require 'sinatra'

module Dynflow
  class WebConsole < Sinatra::Base

    def self.setup(&block)
      Sinatra.new(self) do
        instance_exec(&block)
      end
    end

    web_dir = File.join(File.expand_path('../../../web', __FILE__))

    set :public_folder, File.join(web_dir, 'assets')
    set :views, File.join(web_dir, 'views')
    set :per_page, 10

    helpers ERB::Util

    helpers do
      def world
        settings.world
      end

      def prettyprint(value)
        value = prettyprint_references(value)
        if value
          pretty_value = value.pretty_inspect
          <<-HTML
            <pre class="prettyprint">#{h(pretty_value)}</pre>
          HTML
        else
          ""
        end
      end

      def prettyprint_references(value)
        case value
        when Hash
          value.reduce({}) do |h, (key, val)|
            h.update(key => prettyprint_references(val))
          end
        when Array
          value.map { |val| prettyprint_references(val) }
        when ExecutionPlan::OutputReference
          value.inspect
        else
          value
        end
      end

      def load_action(step)
        world.persistence.load_action(step)
      end

      def step_error(step)
        if step.error
          ([step.error.message] + step.error.backtrace).map do |line|
            "<p>#{h(line)}</p>"
          end.join
        end
      end

      def show_action_data(label, value)
        value_html = prettyprint(value)
        if !value_html.empty?
          <<-HTML
            <p>
              #{h(label)}
              #{value_html}
            </p>
          HTML
        else
          ""
        end
      end

      def atom_css_classes(atom)
        classes = ["atom"]
        step    = @plan.steps[atom.step_id]
        case step.state
        when :success
          classes << "success"
        when :error
          classes << "error"
        when :skipped
          classes << "skipped"
        end
        return classes.join(" ")
      end

      def flow_css_classes(flow, sub_flow = nil)
        classes = []
        case flow
        when Flows::Sequence
          classes << "sequence"
        when Flows::Concurrence
          classes << "concurrence"
        when Flows::Atom
          classes << atom_css_classes(flow)
        else
          raise "Unknown run plan #{run_plan.inspect}"
        end
        classes << atom_css_classes(sub_flow) if sub_flow.is_a? Flows::Atom
        return classes.join(" ")
      end

      def step_css_class(step)
        case step.state
        when :success
          "success"
        when :error
          "danger"
        end
      end

      def progress_width(action)
        if action.state == :error
          100 # we want to show the red bar in full width
        else
          action.progress_done * 100
        end
      end

      def step(step_id)
        @plan.steps[step_id]
      end

      def paginate?
        world.persistence.adapter.pagination?
      end

      def updated_url(new_params)
        url("?" + Rack::Utils.build_query(params.merge(new_params.stringify_keys)))
      end

      def paginated_url(delta)
        h(updated_url(page: [0, page + delta].max))
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

      def page
        (params[:page] || 0).to_i
      end

      def per_page
        (params[:per_page] || 10).to_i
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
                                desc: (params[:desc] == 'true') }
        elsif supported_ordering?('started_at')
          @ordering_options = { order_by: 'started_at', desc: true }
        else
          @ordering_options = {}
        end
        return @ordering_options
      end

      def order_link(attr, label)
        return h(label) unless supported_ordering?(attr)
        new_ordering_options = { order_by: attr.to_s,
                                 desc: false }
        arrow = ""
        if ordering_options[:order_by].to_s == attr.to_s
          arrow = ordering_options[:desc] ? "&#9660;" : "&#9650;"
          new_ordering_options[:desc] = !ordering_options[:desc]
        end
        url = updated_url(new_ordering_options)
        return %{<a href="#{url}"> #{arrow} #{h(label)}</a>}
      end

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
          filters = { 'state' => ['pending', 'running', 'paused'] }
        else
          filters = {}
        end
        @filtering_options = { filters: filters }.with_indifferent_access
        return @filtering_options
      end

      def filter_checkbox(field, values)
        out = "<p>#{field}: %s</p>"
        checkboxes = values.map do |value|
          field_filter = filtering_options[:filters][field]
          checked = field_filter && field_filter.include?(value)
          %{<input type="checkbox" name="filters[#{field}][]" value="#{value}" #{ "checked" if checked }/>#{value}}
        end.join(' ')
        out %= checkboxes
        return out
      end

    end

    get('/') do
      options = HashWithIndifferentAccess.new
      options.merge!(filtering_options)
      options.merge!(pagination_options)
      options.merge!(ordering_options)

      @plans = world.persistence.find_execution_plans(options)
      erb :index
    end

    get('/:id') do |id|
      @plan = world.persistence.load_execution_plan(id)
      erb :show
    end

    post('/:id/resume') do |id|
      plan = world.persistence.load_execution_plan(id)
      if plan.state != :paused
        redirect(url "/#{plan.id}?notice=#{url_encode('The exeuction has to be paused to be able to resume')}")
      else
        world.execute(plan.id)
        redirect(url "/#{plan.id}?notice=#{url_encode('The execution was resumed')}")
      end
    end

    post('/:id/skip/:step_id') do |id, step_id|
      plan = world.persistence.load_execution_plan(id)
      step = plan.steps[step_id.to_i]
      if plan.state != :paused 
        redirect(url "/#{plan.id}?notice=#{url_encode('The exeuction has to be paused to be able to skip')}")
      elsif step.state != :error
        redirect(url "/#{plan.id}?notice=#{url_encode('The step has to be failed to be able to skip')}")
      else
        plan.skip(step)
        redirect(url "/#{plan.id}")
      end
    end

  end
end
