#!/usr/bin/env ruby

require_relative 'example_helper'
require 'logger'

class LaunchToSpace < Dynflow::Action
  include ::Dynflow::Action::Revertible

  def self.revert_action_class
    RevertLaunch
  end

  def plan
    sequence do
      plan_action LoadFuel, 'liquid hydrogen'
      concurrence do
        plan_action LoadCargo, ['tools', 'food', 'goods']
        plan_action LoadCrew, ['pilot', 'navigator']
      end
      plan_action RunPreFlightChecks
      plan_self
    end
  end

  def run
    output[:log] = [
      'All conditions cleared',
      'Launching'
    ]
  end

  def finalize
    output[:log] << 'Launch successful'
  end
end

class RunPreFlightChecks < ::Dynflow::Action
  include ::Dynflow::Action::Revertible

  def self.revert_action_class
    Reverting
  end

  def run
    if ExampleHelper.something_should_fail?
      ExampleHelper.nothing_should_fail!
      raise "Bad weather, launch is not possible"
    end
    output[:log] = 'All checks passed'
  end
end

class Load < Dynflow::Action
  include ::Dynflow::Action::Revertible

  def self.revert_action_class
    constantize self.to_s.gsub(/^Load/, 'Unload')
  end

  def plan(things = [])
    if things.kind_of? Array
      things.each do |value|
        plan_action self.class, value
      end
    else
      plan_self :what => things
    end
  end

  def run
    output[:log] = "Loading #{input[:what]}"
  end
end

class LoadFuel < Load; end
class LoadCrew < Load; end
class LoadCargo < Load; end

class Unload < Dynflow::Action::Reverting
  def run
    output[:log] = "Unloading #{original_input[:kind]} - #{original_input[:what]}"
  end
end

class UnloadFuel < Unload; end
class UnloadCrew < Unload; end
class UnloadCargo < Unload; end

class RevertLaunch < Dynflow::Action::Reverting

  def plan(parent_action)
    super(parent_action)
    if entry_action? && parent_action.run_step.state == :pending
      plan_self
    end
  end

  def finalize
    output[:log] = 'Launch aborted'
  end

end

if $0 == __FILE__
  # Uncomment the following 2 lines to have the execution plan rolled-back automatically
  # world = ExampleHelper.create_world { |config| config.auto_rescue = true }
  # ExampleHelper.set_world world
  ExampleHelper.something_should_fail!
  triggered = ExampleHelper.world.trigger(LaunchToSpace)
  ExampleHelper.world.trigger(LaunchToSpace)

  puts <<-MSG.gsub(/^.*\|/, '')
    |  Execution plan #{triggered.id} failed and was reverted
    |  You can see the details at http://localhost:4567/#{triggered.id}
  MSG

  ExampleHelper.run_web_console
end
