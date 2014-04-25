require 'rubygems'
require 'json'
module Dynflow
  class Exporter

    attr_reader :actions, :execution_plan

    def initialize(world)
      @world = world
      @actions = []
      @execution_plan = {}
    end

    def export_execution_plan(execution_plan_id)
      execution_plan = @world.persistence.load_execution_plan(execution_plan_id)
      @execution_plan = execution_plan.to_hash
      @execution_plan[:steps] = execution_plan.steps.map { |_, step| step.to_hash }
    end

    def export_action(execution_plan_id, action_id)
      action = @world.persistence.adapter.load_action(execution_plan_id, action_id)
      @actions << action.to_hash
    end

    def export_to_dir(dir)
      Dir.mkdir(dir) unless Dir.exists?(dir)
      unless @execution_plan.empty?
        Dir.mkdir("#{dir}/#{@execution_plan[:id]}") unless Dir.exists?("#{dir}/#{@execution_plan[:id]}")
        File.open("#{dir}/#{@execution_plan[:id]}/plan.json",'w') do |f|
          f.write(JSON.generate(@execution_plan))
          f.close()
        end
        @execution_plan = {}
      end
      unless @actions.empty?
        Dir.mkdir("#{dir}/#{@actions.first['execution_plan_id']}") unless Dir.exists?("#{dir}/#{@actions.first['execution_plan_id']}")
        @actions.each do |action|
          File.open("#{dir}/#{action['execution_plan_id']}/action-#{action['id']}.json",'w') do |f|
            f.write(JSON.generate(action))
            f.close()
          end
        end
        @actions = []
      end
    end
  end
end
