module Dynflow
  module Web
    module ConsoleHelpers
      def validation_result_css_class(result)
        if result == :valid
          "success"
        else
          "danger"
        end
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
        world.persistence.load_action_for_presentation(@plan, step.action_id, step)
      end

      def step_error(step)
        if step.error
          ['<pre>',
           "#{h(step.error.message)} (#{h(step.error.exception_class)})\n",
           h(step.error.backtrace.join("\n")),
           '</pre>'].join
        end
      end

      def show_world(world_id)
        if registered_world = world.coordinator.find_worlds(false, id: world_id).first
          "%{world_id} %{world_meta}" % { world_id: world_id, world_meta: registered_world.meta.inspect }
        else
          world_id
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
          "danger"
        else
          "default"
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
        url(request.path_info + "?" + Rack::Utils.build_nested_query(params.merge(Utils.stringify_keys(new_params))))
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
  end
end
