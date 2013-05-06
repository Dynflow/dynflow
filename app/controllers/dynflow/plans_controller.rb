require_dependency "dynflow/application_controller"

module Dynflow
  class PlansController < ApplicationController

    before_filter :authenticate

    def index
      @plans = Dynflow::Bus.persisted_plans
    end

    def show
      @plan = Dynflow::Bus.persisted_plan(params[:id])
    end

    def resume
      @plan = Dynflow::Bus.persisted_plan(params[:id])
      Dynflow::Bus.resume(@plan)
      redirect_to plan_path(:id => @plan.persistence.persistence_id), :notice => "Resume"
    end

    def skip_step
      @step = Dynflow::Bus.persisted_step(params[:step_id])
      Dynflow::Bus.skip(@step)
      @plan = Dynflow::Bus.persisted_plan(params[:id])
      Dynflow::Bus.resume(@plan)
      redirect_to plan_path(:id => @plan.persistence.persistence_id), :notice => "Skip"
    end

    protected

    def authenticate
      # TODO: proper authentication mechanism
      if defined?(User) && User.respond_to?(:current=)
        User.current = User.first
      end
    end
  end
end
