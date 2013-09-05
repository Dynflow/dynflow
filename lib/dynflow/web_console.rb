require 'dynflow'
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
          pretty_value = if !value.is_a?(Hash) && !value.is_a?(Array)
                           value.inspect
                         elsif value.empty?
                           MultiJson.dump(value, :pretty => false)
                         else
                           MultiJson.dump(value, :pretty => true)
                         end
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
        if step.state == :error
          action = world.persistence.adapter.load_action(step.execution_plan_id,
                                                         step.action_id)
          return action[:error]
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
          atom_css_classes(flow)
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

      def step(step_id)
        @plan.steps[step_id]
      end

      def paginate?
        world.persistence.adapter.pagination?
      end

      def paginated_url(delta)
        h(url("?" + Rack::Utils.build_query(params.merge('page' => [0, page + delta].max))))
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

    end

    get('/') do
      options = {}
      options.merge!(pagination_options)

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
