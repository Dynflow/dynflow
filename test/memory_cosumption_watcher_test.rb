# frozen_string_literal: true
require_relative 'test_helper'
require 'fileutils'
require 'dynflow/watchers/memory_consumption_watcher'

module Dynflow
  module MemoryConsumptionWatcherTest
    describe ::Dynflow::Watchers::MemoryConsumptionWatcher do
      let(:world) { Minitest::Mock.new('world') }
      describe 'initialization' do
        it 'starts a timer on the world' do
          clock = Minitest::Mock.new('clock')
          world.expect(:clock, clock)
          init_interval = 1000
          clock.expect(:ping, true) do |clock_who, clock_when, _|
            clock_when.must_equal init_interval
          end

          Dynflow::Watchers::MemoryConsumptionWatcher.new world, 1, initial_wait: init_interval

          clock.verify
        end
      end

      describe 'polling' do
        let(:memory_info_provider) { Minitest::Mock.new('memory_info_provider') }
        it 'continues to poll, if memory limit is not exceeded' do
          clock = Minitest::Mock.new('clock')
          # define method clock
          world.expect(:clock, clock)
          init_interval = 1000
          polling_interval = 2000
          clock.expect(:ping, true) do |clock_who, clock_when, _|
            clock_when.must_equal init_interval
            true
          end
          clock.expect(:ping, true) do |clock_who, clock_when, _|
            clock_when.must_equal polling_interval
            true
          end
          memory_info_provider.expect(:bytes, 0)

          # stub the clock method to always return our mock clock
          world.stub(:clock, clock) do
            watcher = Dynflow::Watchers::MemoryConsumptionWatcher.new(
              world,
              1,
              initial_wait: init_interval,
              memory_info_provider: memory_info_provider,
              polling_interval: polling_interval
            )
            watcher.check_memory_state
          end

          clock.verify
          memory_info_provider.verify
        end

        it 'terminates the world, if memory limit reached' do
          clock = Minitest::Mock.new('clock')
          # define method clock
          world.expect(:clock, clock)
          world.expect(:terminate, true)

          init_interval = 1000
          clock.expect(:ping, true) do |clock_who, clock_when, _|
            clock_when.must_equal init_interval
            true
          end
          memory_info_provider.expect(:bytes, 10)

          # stub the clock method to always return our mock clock
          watcher = Dynflow::Watchers::MemoryConsumptionWatcher.new(
            world,
            1,
            initial_wait: init_interval,
            memory_info_provider: memory_info_provider
          )
          watcher.check_memory_state

          clock.verify
          memory_info_provider.verify
          world.verify
        end
      end
    end
  end
end
