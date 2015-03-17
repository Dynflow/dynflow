
module Dynflow
  module Web
    class Console < Sinatra::Base

      set :public_folder, Web.web_dir('assets')
      set :views, Web.web_dir('views')
      set :per_page, 10

      helpers ERB::Util
      helpers Web::FilteringHelpers
      helpers Web::WorldHelpers
      helpers Web::ConsoleHelpers

      get('/') do
        options = find_execution_plans_options
        @plans = world.persistence.find_execution_plans(options)
        erb :index
      end

      get('/:execution_plan_id/actions/:action_id/sub_plans') do |execution_plan_id, action_id|
        options = find_execution_plans_options(true)
        options[:filters].update('caller_execution_plan_id' => execution_plan_id,
                                 'caller_action_id' => action_id)
        @plans = world.persistence.find_execution_plans(options)
        erb :index
      end

      get('/worlds') do
        @worlds = world.coordinator.find_worlds
        erb :worlds
      end

      post('/worlds/:id/ping') do |id|
        timeout = 5
        ping_response = world.ping(id, timeout).wait
        if ping_response.rejected?
          response = "failed: #{ping_response.reason.message}"
          inactive_world_id = id
        else
          response = 'pong'
        end
        redirect(url "/worlds?notice=#{url_encode(response)}&inactive_world_id=#{inactive_world_id}")
      end

      post('/worlds/:id/invalidate') do |id|
        invalidated_world = world.persistence.find_worlds(false, id: id).first
        unless invalidated_world
          response = "World #{id} not found"
        else
          begin
            world.invalidate(invalidated_world)
            response = "World #{invalidated_world.id} invalidated"
          rescue => e
            response = "World invalidation failed: #{e.message}"
          end
        end
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
