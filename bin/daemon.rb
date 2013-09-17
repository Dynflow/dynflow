#!/usr/bin/env ruby

root_path    = File.expand_path(File.join(File.dirname(__FILE__), '..'))
dynflow_path = File.join(root_path, 'lib')
$LOAD_PATH << dynflow_path unless $LOAD_PATH.include? dynflow_path

require 'dynflow'
require 'tmpdir'

socket              = File.join(Dir.tmpdir, 'dynflow_socket')
persistence_adapter = Dynflow::PersistenceAdapters::Sequel.new ARGV[0] || 'sqlite://db.sqlite'
world               = Dynflow::SimpleWorld.new persistence_adapter: persistence_adapter
listener            = Dynflow::Executors::RemoteViaSocket::Listener.new world, socket

load File.join(root_path, 'test', 'code_workflow_example.rb')

Dynflow::Daemon.new(listener, world).run
