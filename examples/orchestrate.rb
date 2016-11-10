#!/usr/bin/env ruby

example_description = <<DESC
  Orchestrate Example
  ===================

  This example simulates a workflow of setting up an infrastructure, using
  more high-level steps in CreateInfrastructure, that expand to smaller steps
  of PrepareDisk, CraeteVM etc.

  It shows the possibility to run the independend actions concurrently, chaining
  the actions (passing the output of PrepareDisk action to CreateVM, automatically
  detecting the dependency making sure to run the one before the other).

  It also simulates a failure and demonstrates the Dynflow ability to rescue
  from the error and consinue with the run.

  Once the Sinatra web console starts, you can navigate to http://localhost:4567
  to see what's happening in the Dynflow world.

DESC

require_relative 'example_helper'

module Orchestrate

  class CreateInfrastructure < Dynflow::Action

    def plan
      sequence do
        concurrence do
          plan_action(CreateMachine, 'host1', 'db')
          plan_action(CreateMachine, 'host2', 'storage')
        end
        plan_action(CreateMachine,
                    'host3',
                    'web_server',
                    :db_machine => 'host1',
                    :storage_machine => 'host2')
      end
    end
  end

  class CreateMachine < Dynflow::Action

    def plan(name, profile, config_options = {})
      prepare_disk = plan_action(PrepareDisk, 'name' => name)
      create_vm    = plan_action(CreateVM,
                                 :name => name,
                                 :disk => prepare_disk.output['path'])
      plan_action(AddIPtoHosts, :name => name, :ip => create_vm.output[:ip])
      plan_action(ConfigureMachine,
                  :ip => create_vm.output[:ip],
                  :profile => profile,
                  :config_options => config_options)
      plan_self(:name => name)
    end

    def finalize
      # this is called after run methods of the actions in the
      # execution plan were finished
    end

  end

  class Base < Dynflow::Action
    def sleep!
      sleep(rand(2))
    end
  end

  class PrepareDisk < Base

    input_format do
      param :name
    end

    output_format do
      param :path
    end

    def run
      sleep!
      output[:path] = "/var/images/#{input[:name]}.img"
    end

  end

  class CreateVM < Base

    input_format do
      param :name
      param :disk
    end

    output_format do
      param :ip
    end

    def run
      sleep!
      output[:ip] = "192.168.100.#{rand(256)}"
    end

  end

  class AddIPtoHosts < Base

    input_format do
      param :ip
    end

    def run
      sleep!
    end

  end

  class ConfigureMachine < Base

    input_format do
      param :ip
      param :profile
      param :config_options
    end

    def run
      # for demonstration of resuming after error
      if ExampleHelper.something_should_fail?
        ExampleHelper.nothing_should_fail!
        puts <<-MSG.gsub(/^.*\|/, '')

                | Execution plan #{execution_plan_id} is failing
                | You can resume it at http://localhost:4567/#{execution_plan_id}

        MSG
        raise "temporary unavailabe"
      end

      sleep!
    end

  end
end

if $0 == __FILE__
  ExampleHelper.world.action_logger.level = Logger::INFO
  ExampleHelper.something_should_fail!
  ExampleHelper.world.trigger(Orchestrate::CreateInfrastructure)
  Thread.new do
    9.times do
      ExampleHelper.world.trigger(Orchestrate::CreateInfrastructure)
    end
  end
  puts example_description
  ExampleHelper.run_web_console
end
