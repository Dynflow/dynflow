
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

      get('/status') do
        # TODO: create a separate page for the overall status, linking
        # to the more detailed pages
        redirect to '/worlds'
      end

      get('/worlds') do
        load_worlds
        erb :worlds
      end

      post('/worlds/execution_status') do
        load_worlds
        @executors.each do |w|
          hash = world.get_execution_status(w.data['id'], nil, 5).value!
          hash.each do |_queue_name, info|
            info[:queue_size] = info[:execution_status].values.reduce(:+) || 0
          end
          w.data.update(:status => hash)
        end
        erb :worlds
      end

      post('/worlds/check') do
        @validation_results = world.worlds_validity_check(params[:invalidate])
        load_worlds
        erb :worlds
      end

      post('/worlds/:id/check') do |id|
        @validation_results = world.worlds_validity_check(params[:invalidate], id: params[:id])
        load_worlds
        erb :worlds
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

      post('/:id/cancel') do |id|
        plan = world.persistence.load_execution_plan(id)
        cancel_events = plan.cancel
        if cancel_events.empty?
          redirect(url "/#{plan.id}?notice=#{url_encode('Not possible to cancel at the moment')}")
        else
          redirect(url "/#{plan.id}?notice=#{url_encode("The cancel event has been propagated")}")
        end
      end

      post('/:id/rollback') do |id|
        plan = world.persistence.load_execution_plan(id)
        plan.rescue_from_error
        redirect(url "/#{plan.id}?notice=#{url_encode('The rollback was triggered')}")
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
