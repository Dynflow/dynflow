
require 'sprockets'
require 'sprockets-helpers'

module Dynflow
  module Web
    class LegacyConsole < Sinatra::Base

      set :public_folder, Web.web_dir('assets')
      set :views, Web.web_dir('views')
      set :per_page, 10

      helpers ERB::Util
      helpers Web::FilteringHelpers
      helpers Web::WorldHelpers
      helpers do

        def world
          settings.world
        end

        def prettify_value(value)
          YAML.dump(value)
        end

        def prettyprint(value)
          value = prettyprint_references(value)
          if value
            pretty_value = prettify_value(value)
            <<-HTML
              <pre class="prettyprint lang-yaml">#{h(pretty_value)}</pre>
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

        def duration_to_s(duration)
          h("%0.2fs" % duration)
        end

        def load_action(step)
          world.persistence.load_action(step)
        end

        def step_error(step)
          if step.error
            ['<pre>',
             "#{h(step.error.message)} (#{h(step.error.exception_class)})\n",
             h(step.error.backtrace.join("\n")),
             '</pre>'].join
          end
        end

        def show_action_data(label, value)
          value_html = prettyprint(value)
          if !value_html.empty?
            <<-HTML
              <p>
                <b>#{h(label)}</b>
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
          when :skipped, :skipping
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
            "important"
          end
        end

        def progress_width(step)
          if step.state == :error
            100 # we want to show the red bar in full width
          else
            step.progress_done * 100
          end
        end

        def step(step_id)
          @plan.steps[step_id]
        end

        def updated_url(new_params)
          url("?" + Rack::Utils.build_nested_query(params.merge(new_params.stringify_keys)))
        end

        def paginated_url(delta)
          h(updated_url(page: [0, page + delta].max.to_s))
        end

        def order_link(attr, label)
          return h(label) unless supported_ordering?(attr)
          new_ordering_options = { order_by: attr.to_s,
                                   desc:     false }
          arrow                = ""
          if ordering_options[:order_by].to_s == attr.to_s
            arrow                       = ordering_options[:desc] ? "&#9660;" : "&#9650;"
            new_ordering_options[:desc] = !ordering_options[:desc]
          end
          url = updated_url(new_ordering_options)
          return %{<a href="#{url}"> #{arrow} #{h(label)}</a>}
        end

        def filter_checkbox(field, values)
          out        = "<p>#{field}: %s</p>"
          checkboxes = values.map do |value|
            field_filter = filtering_options[:filters][field]
            checked      = field_filter && field_filter.include?(value)
            %{<input type="checkbox" name="filters[#{field}][]" value="#{value}" #{ "checked" if checked }/>#{value}}
          end.join(' ')
          out        %= checkboxes
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

      get('/worlds') do
        @worlds = world.persistence.find_worlds({})
        erb :worlds
      end

      get('/:id') do |id|
        @plan = world.persistence.load_execution_plan(id)
        @notice = params[:notice]
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

      post('/:id/cancel/:step_id') do |id, step_id|
        plan = world.persistence.load_execution_plan(id)
        step = plan.steps[step_id.to_i]
        if step.cancellable?
          world.event(plan.id, step.id, Dynflow::Action::Cancellable::Cancel)
          redirect(url "/#{plan.id}?notice=#{url_encode('The step was asked to cancel')}")
        else
          redirect(url "/#{plan.id}?notice=#{url_encode('The step does not support cancelling')}")
        end
      end

    end
  end
end
