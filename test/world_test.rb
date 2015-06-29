require_relative 'test_helper'
require 'fileutils'

module Dynflow
  module WorldTest
    describe World do
      let(:world) { WorldFactory.create_world }
      let(:world_with_custom_meta) { WorldFactory.create_world { |c| c.meta = { 'fast' => true } } }

      describe '#meta' do
        it 'by default informs about the hostname and the pid running the world' do
          registered_world = world.coordinator.find_worlds(false, id: world.id).first
          registered_world.meta.must_equal('hostname' => Socket.gethostname, 'pid' => Process.pid)
        end

        it 'is configurable' do
          registered_world = world.coordinator.find_worlds(false, id: world_with_custom_meta.id).first
          registered_world.meta.must_equal('fast' => true)
        end
      end
    end
  end
end
