# frozen_string_literal: true

require_relative 'test_helper'
require 'mocha/minitest'

require 'sidekiq'
require 'sidekiq/api'
require 'dynflow/executors/sidekiq/core'

module Dynflow
  module SidekiqPruneOrphanedQueuesTest
    describe Executors::Sidekiq::Core do
      before do
        Executors::Sidekiq::Core.any_instance.stubs(:wait_for_orchestrator_lock)
        Executors::Sidekiq::Core.any_instance.stubs(:begin_startup!)
      end

      after do
        ::Dynflow.instance_variable_set('@process_world', nil)
        ::Sidekiq.redis do |conn|
          conn.smembers('queues').each do |name|
            next unless name.start_with?('dynflow_orchestrator:')
            conn.del("queue:#{name}")
            conn.srem?('queues', name)
          end
        end
      end

      let(:world) do
        world = WorldFactory.create_world { |c| c.executor = Executors::Sidekiq::Core }
        ::Dynflow.instance_variable_set('@process_world', world)
        world
      end

      def seed_queue(name)
        ::Sidekiq.redis do |conn|
          conn.sadd?('queues', name)
          conn.lpush("queue:#{name}", '{}')
        end
      end

      def queue_names
        ::Sidekiq::Queue.all.map(&:name)
      end

      it 'removes orchestrator queues for worlds without an active executor, keeps the rest' do
        active_queue = "dynflow_orchestrator:#{world.id}"
        stale_queue = 'dynflow_orchestrator:stale-world-id'
        seed_queue(active_queue)
        seed_queue(stale_queue)

        world.executor.core.ask!(:prune_orphaned_queues)

        _(queue_names).must_include active_queue
        _(queue_names).wont_include stale_queue
      end

      it 'leaves unrelated queues untouched' do
        other_queue = 'default'
        seed_queue(other_queue)

        world.executor.core.ask!(:prune_orphaned_queues)

        _(queue_names).must_include other_queue

        ::Sidekiq.redis do |conn|
          conn.del("queue:#{other_queue}")
          conn.srem?('queues', other_queue)
        end
      end
    end
  end
end
