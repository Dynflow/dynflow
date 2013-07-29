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
        if value
          pretty_value = if !value.is_a?(Hash) && !value.is_a?(Array)
                           value.inspect
                         elsif value.empty?
                           MultiJson.dump(value, :pretty => false)
                         else
                           MultiJson.dump(value, :pretty => true)
                         end
          <<HTML
<pre class="prettyprint">#{h(pretty_value)}</pre>
HTML
        else
          ""
        end
      end

      def load_action(step)
        world.persistence.load_step_action(step)
      end

      def show_action_data(label, value)
        value_html = prettyprint(value)
        if !value_html.empty?
        <<HTML
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
        case atom.step.state
        when :success then classes << "success"
        when :error then classes << "error"
        end
        return classes.join(" ")
      end

      def flow_css_classes(flow, sub_flow = nil)
        classes = []
        case flow
        when Flows::Sequence then classes << "sequence"
        when Flows::Concurrence then classes << "concurrence"
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
        when :success then "success"
        when :error then "danger"
        end
      end

    end

    get('/') do
      @plans = world.persistence.find_execution_plans
      erb :index
    end

    get('/:id') do |id|
      @plan = world.persistence.load_execution_plan(id)
      erb :show
    end

  end
end
