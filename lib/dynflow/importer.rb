require 'json'
require 'pry'
module Dynflow
  class Importer

    def initialize(world)
      @world = world
    end

    def import_from_dir(path)
      execution_plan_hash = {}
      File.open("#{path}/plan.json") do |execution_plan_file|
        execution_plan_hash = JSON.parse(execution_plan_file.read(), {symbolize_names: true})
        execution_plan_file.close()
      end
      execution_plan = Dynflow::ExecutionPlan.new_from_hash(execution_plan_hash,@world,check_steps=false)
      raise ActionMissing, "Action files are missing" unless all_action_files?(execution_plan, path)
      execution_plan.save
      Dir.glob("#{path}/action-*.json").each do |action_file|
        f = File.open(action_file)
        action = JSON.parse(f.read,{symbolize_names: true})
        @world.persistence.adapter.save_action(execution_plan.id, action[:id], action)
        f.close()
      end
      execution_plan.steps.each { |step_id, step| @world.persistence.save_step(step) }
    end

    private

    def all_action_files?(execution_plan,path)
      action_ids = []
      Dir.glob("#{path}/action-*.json") { |file| action_ids << /action-(\d+).json$/.match(file)[1].to_i }
      (execution_plan.steps.map { |_,step| step.action_id } - action_ids).count == 0
    end
  end

  class ActionMissing < StandardError
  end

end

