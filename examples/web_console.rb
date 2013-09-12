# Demo for Dynflow web console
# usage: ruby web_console.rb

$:.unshift(File.expand_path('../../lib', __FILE__))

require 'dynflow'
require_relative 'orchestrate'

world = Dynflow::SimpleWorld.new

require 'dynflow/web_console'
dynflow_console = Dynflow::WebConsole.setup do
  set :world, world
end

11.times do
  world.trigger(Orchestrate::CreateInfrastructure)
end

puts <<MESSAGE
=============================================
  See the console at http://localhost:4567/
=============================================
MESSAGE
dynflow_console.run!
