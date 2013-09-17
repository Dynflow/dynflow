#!/usr/bin/env ruby

root_path    = File.expand_path(File.join(File.dirname(__FILE__), '..'))
dynflow_path = File.join(root_path, 'lib')
$LOAD_PATH << dynflow_path unless $LOAD_PATH.include? dynflow_path

require 'dynflow'
require 'tmpdir'

socket_path         = File.join(Dir.tmpdir, 'dynflow_socket')
persistence_adapter = Dynflow::PersistenceAdapters::Sequel.new ARGV[0] || 'sqlite://db.sqlite'


class RemoteWorld < Dynflow::SimpleWorld
  def default_options
    socket_path = Dir.tmpdir + '/dynflow_socket'
    super.merge :executor => Dynflow::Executors::RemoteViaSocket.new(self, socket_path)
  end
end

world = RemoteWorld.new persistence_adapter: persistence_adapter

load File.join(root_path, 'test', 'code_workflow_example.rb')

loop do
  world.trigger Dynflow::CodeWorkflowExample::Slow, 1
  sleep 0.5
  p 'tick'
end
