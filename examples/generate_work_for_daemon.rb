#!/usr/bin/env ruby

root_path    = File.expand_path(File.join(File.dirname(__FILE__), '..'))
dynflow_path = File.join(root_path, 'lib')
$LOAD_PATH << dynflow_path unless $LOAD_PATH.include? dynflow_path

require 'dynflow'
require 'tmpdir'

socket_path         = File.join(Dir.tmpdir, 'dynflow_socket')
persistence_adapter = Dynflow::PersistenceAdapters::Sequel.new ARGV[0] || 'sqlite://db.sqlite'

world = Dynflow::SimpleWorld.new do |world|
  { persistence_adapter: persistence_adapter,
    executor:            Dynflow::Executors::RemoteViaSocket.new(world, socket_path) }
end

load File.join(root_path, 'test', 'code_workflow_example.rb')

loop do
  world.trigger Dynflow::CodeWorkflowExample::Slow, 1
  sleep 0.5
  p 'tick'
end
