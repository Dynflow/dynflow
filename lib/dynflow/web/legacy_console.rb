
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
      helpers Web::LegacyHelpers

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

      post('/worlds/:id/ping') do |id|
        timeout = 5
        ping_response = world.ping(id, timeout).wait
        response = ping_response.rejected? ? "failed: #{ping_response.reason.message}" : 'pong'
        redirect(url "/worlds?notice=#{url_encode(response)}")
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
