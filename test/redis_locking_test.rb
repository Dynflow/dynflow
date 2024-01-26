# frozen_string_literal: true

require_relative 'test_helper'
require 'mocha/minitest'
require 'minitest/stub_const'
require 'ostruct'
require 'sidekiq'
require 'dynflow/executors/sidekiq/core'

module Dynflow
  module RedisLockingTest
    describe Executors::Sidekiq::RedisLocking do
      class Orchestrator
        include Executors::Sidekiq::RedisLocking

        attr_accessor :logger

        def initialize(world, logger)
          @world = world
          @logger = logger
        end
      end

      class Logger
        attr_reader :logs
        def initialize
          @logs = []
        end

        [:info, :error, :fatal].each do |key|
          define_method key do |message|
            @logs << [key, message]
          end
        end
      end

      after do
        ::Sidekiq.redis do |conn|
          conn.del Executors::Sidekiq::RedisLocking::REDIS_LOCK_KEY
        end
      end

      def redis_orchestrator_id
        ::Sidekiq.redis do |conn|
          conn.get Executors::Sidekiq::RedisLocking::REDIS_LOCK_KEY
        end
      end

      let(:world)  { OpenStruct.new(:id => '12345') }
      let(:world2) { OpenStruct.new(:id => '67890') }
      let(:orchestrator)  { Orchestrator.new(world, Logger.new) }
      let(:orchestrator2) { Orchestrator.new(world2, Logger.new) }

      it 'acquires the lock when it is not taken' do
        orchestrator.wait_for_orchestrator_lock
        logs = orchestrator.logger.logs
        _(redis_orchestrator_id).must_equal world.id
        _(logs).must_equal [[:info, 'Acquired orchestrator lock, entering active mode.']]
      end

      it 'reacquires the lock if it was lost' do
        orchestrator.reacquire_orchestrator_lock
        logs = orchestrator.logger.logs
        _(redis_orchestrator_id).must_equal world.id
        _(logs).must_equal [[:error, 'The orchestrator lock was lost, reacquired']]
      end

      it 'terminates the process if lock was stolen' do
        orchestrator.wait_for_orchestrator_lock
        Process.expects(:kill)
        orchestrator2.reacquire_orchestrator_lock
        logs = orchestrator2.logger.logs
        _(redis_orchestrator_id).must_equal world.id
        _(logs).must_equal [[:fatal, 'The orchestrator lock was stolen by 12345, aborting.']]
      end

      it 'polls for the lock availability' do
        Executors::Sidekiq::RedisLocking.stub_const(:REDIS_LOCK_TTL, 1) do
          Executors::Sidekiq::RedisLocking.stub_const(:REDIS_LOCK_POLL_INTERVAL, 0.5) do
            orchestrator.wait_for_orchestrator_lock
            _(redis_orchestrator_id).must_equal world.id
            orchestrator2.wait_for_orchestrator_lock
          end
        end

        _(redis_orchestrator_id).must_equal world2.id
        passive, active = orchestrator2.logger.logs
        _(passive).must_equal [:info, 'Orchestrator lock already taken, entering passive mode.']
        _(active).must_equal [:info, 'Acquired orchestrator lock, entering active mode.']
      end
    end
  end
end
