require 'dynflow'
require 'sinatra'

module Dynflow
  class WebConsole < Sinatra::Base

    def self.setup(&block)
      Sinatra.new(self) do
        instance_exec(&block)
      end
    end

    dir = File.join(Dynflow::ROOT_PATH, 'web')

    set :public_folder, File.join(dir, 'assets')
    set :views, File.join(dir, 'views')
    set :per_page, 10

    helpers ERB::Util

    helpers do
      def bus
        settings.bus
      end

      def prettyprint(value)
        if value
          pretty_value = if value.empty?
                           JSON.generate(value)
                         else
                           JSON.pretty_generate(value)
                         end
          <<HTML
<pre class="prettyprint">#{h(pretty_value)}</pre>
HTML
        else
          ""
        end
      end

      def page
        [(params[:page] || 1).to_i, 1].max
      end

      def paginated_url(delta)
        h(url("?" + Rack::Utils.build_query(params.merge(:page => page + delta))))
      end
    end

    get('/') do
      status = params[:status] || 'not_finished'
      @plans = bus.persisted_plans(status, :page => page, :per_page => settings.per_page)
      erb :index
    end

    get('/:persisted_plan_id') do |id|
      @plan = bus.persisted_plan(id)
      @notice = params[:notice]
      erb :show
    end

    post('/:persisted_plan_id/resume') do |id|
      @plan = bus.persisted_plan(id)
      bus.resume(@plan)
      redirect(url "/#{id}?notice=#{url_encode('The action was resumed')}")
    end

    post('/:persisted_plan_id/steps/:persisted_step_id/skip') do |id, step_id|
      @step = bus.persisted_step(step_id)
      bus.skip(@step)
      @plan = bus.persisted_plan(id)
      bus.resume(@plan)
      redirect(url "/#{id}?notice=#{url_encode('The step was skipped and the action was resumed')}")
    end

  end
end
