#!/usr/bin/env ruby

require_relative 'example_helper'
require 'logger'

class LaunchToSpace < Dynflow::Action
  include ::Dynflow::Action::Revertible

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

  def revert_run
    output[:log] = ['Aborting launch']
  end

  def revert_plan
    output[:log] << 'Launch aborted'
  end
end

class RunPreFlightChecks < ::Dynflow::Action
  include ::Dynflow::Action::Revertible

  def run
    if ExampleHelper.something_should_fail?
      ExampleHelper.nothing_should_fail!
      raise "Bad weather, launch is not possible"
    end
    output[:log] = 'All checks passed'
  end

  # def revert_run
  #   # Not doing anything
  # end

  # def revert_plan
  #   # Not doing anything either
  # end
end

class Load < Dynflow::Action
  include ::Dynflow::Action::Revertible

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
    output[:log] = ["Loading #{input[:what]}"]
  end

  def revert_run
    output[:log] = ["Unloading #{original_input[:what]}"]
  end

  def revert_plan
    output[:log] << "Cleaning up after unloading #{original_input[:what]}"
  end
end

class LoadFuel < Load; end
class LoadCrew < Load; end
class LoadCargo < Load; end

if $0 == __FILE__
  # Uncomment the following 2 lines to have the execution plan rolled-back automatically
  # world = ExampleHelper.create_world { |config| config.auto_rescue = true }
  # ExampleHelper.set_world world
  ExampleHelper.something_should_fail!
  triggered = ExampleHelper.world.trigger(LaunchToSpace)
  ExampleHelper.world.trigger(LaunchToSpace)

  puts <<-MSG.gsub(/^.*\|/, '')
    |  Execution plan #{triggered.id} failed and can be reverted
    |  You can see the details at http://localhost:4567/#{triggered.id}
  MSG

  ExampleHelper.run_web_console
end
