#!/usr/bin/env ruby
# encoding: utf-8

require "rubygems"
require "stomp"

$:.unshift(File.expand_path('../../lib', __FILE__))
require 'dynflow'
require '../katello/config/environment'
require File.expand_path('../../examples/workflow', __FILE__)

class ScenarioRunner

  def initialize(args={})
    if args[:method] == 'stomp'
      initiator = Dynflow::Initiators::StompInitiator.new
    else
      initiator = Dynflow::Initiators::ExecutorInitiator.new
    end

    @manager = Dynflow::Manager.new({
      :persistence_driver => Dynflow::Persistence::ActiveRecordDriver.new,
      :serialization_driver => Dynflow::Serialization::SimpleSerializationDriver.new,
      :initiator => initiator
    })
    run_scenario
  end

  def run_scenario
    scenario = Dynflow::ArticleScenario.new
    scenario.run(@manager)
  end

end

if ARGV.first == 'stomp'
  c = ScenarioRunner.new({:method => 'stomp'})
else
  c = ScenarioRunner.new({:simple => 'simple'})
end
