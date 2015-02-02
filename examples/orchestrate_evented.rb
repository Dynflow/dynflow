#!/usr/bin/env ruby

require_relative 'example_helper'

example_description = <<DESC
  Orchestrate Evented Example
  ===========================

  This example, how the `examples/orchestrate.rb` can be updated to not block
  the threads while waiting for external tasks. In this cases, we usually wait
  most of the time: and we can suspend the run of the action while waiting,
  for the event. Therefore we suspend the action in the run, ask the world.clock
  to wake us up few seconds later, so that the thread pool can do something useful
  in the meantime.

  Additional benefit besides being able to do more while waiting is allowing to
  send external events to the action while it's suspended. One use case is being
  able to cancel the action while it's running.

  Once the Sinatra web console starts, you can navigate to http://localhost:4567
  to see what's happening in the Dynflow world.

DESC

module OrchestrateEvented

  class CreateInfrastructure < Dynflow::Action

    def plan(get_stuck = false)
      sequence do
        concurrence do
          plan_action(CreateMachine, 'host1', 'db', get_stuck: get_stuck)
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
    end

  end

  class Base < Dynflow::Action

    Finished = Algebrick.atom

    def run(event = nil)
      match(event,
            (on Finished do
               on_finish
             end),
            (on Dynflow::Action::Skip do
               # do nothing
             end),
            (on nil do
               suspend { |suspended_action| world.clock.ping suspended_action, rand(1), Finished }
             end))
    end

    def on_finish
      raise NotImplementedError
    end

  end

  class PrepareDisk < Base

    input_format do
      param :name
    end

    output_format do
      param :path
    end

    def on_finish
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

    def on_finish
      output[:ip] = "192.168.100.#{rand(256)}"
    end

  end

  class AddIPtoHosts < Base

    input_format do
      param :ip
    end

    def on_finish
    end

  end

  class ConfigureMachine < Base

    # thanks to this Dynflow knows this action can be politely
    # asked to get canceled
    include ::Dynflow::Action::Cancellable

    input_format do
      param :ip
      param :profile
      param :config_options
    end

    def run(event = nil)
      if event == Dynflow::Action::Cancellable::Cancel
        output[:message] = "I was cancelled but we don't care"
      else
        super
      end
    end

    def on_finish
      if input[:config_options][:get_stuck]
        puts <<-MSG.gsub(/^.*\|/, '')

            | Execution plan #{execution_plan_id} got stuck
            | You can cancel the stucked step at
            | http://localhost:4567/#{execution_plan_id}

        MSG
        # we suspend the action but don't plan the wakeup event,
        # causing it to wait forever (till we cancel it)
        suspend
      end
    end

  end

end

if $0 == __FILE__
  ExampleHelper.world.trigger(OrchestrateEvented::CreateInfrastructure)
  ExampleHelper.world.trigger(OrchestrateEvented::CreateInfrastructure, true)
  puts example_description
  ExampleHelper.run_web_console
end
