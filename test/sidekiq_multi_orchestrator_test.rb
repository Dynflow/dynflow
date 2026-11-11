# frozen_string_literal: true

require_relative 'test_helper'
require 'mocha/minitest'

require 'sidekiq'
require 'sidekiq/api'
require 'dynflow/executors/sidekiq/core'

module Dynflow
  module SidekiqMultiOrchestratorTest
    describe Executors::Sidekiq::Core do
      after do
        ::Dynflow.instance_variable_set('@process_world', nil)
      end

      # @param subqueue [String, nil] the per-orchestrator queue (e.g. "dynflow_orchestrator:abc") this
      #   "process" is configured to listen on, or nil to simulate the legacy shared-queue setup
      def build_world(subqueue: nil, id: nil)
        ::Sidekiq.stubs(:configure_server).returns(subqueue)
        world = WorldFactory.create_world do |c|
          c.executor = Executors::Sidekiq::Core
          c.id = id if id
        end
        ::Dynflow.instance_variable_set('@process_world', world)
        world
      end

      # digs out the actual Sidekiq::Core instance behind the actor reference, mirroring
      # the get_director helper in test_helper.rb
      def raw_core(world)
        world.executor.instance_variable_get('@core').instance_variable_get('@core').context
      end

      describe 'reply queue selection' do
        it 'falls back to the shared queue when no per-orchestrator queue is configured' do
          Executors::Sidekiq::Core.any_instance.expects(:wait_for_orchestrator_lock)
          Executors::Sidekiq::Core.any_instance.expects(:begin_startup!)
          world = build_world(subqueue: nil)
          _(raw_core(world).instance_variable_get('@reply_queue')).must_equal 'dynflow_orchestrator'
        end

        it 'uses the per-orchestrator queue when one is configured' do
          Executors::Sidekiq::Core.any_instance.expects(:wait_for_orchestrator_lock).never
          Executors::Sidekiq::Core.any_instance.expects(:begin_startup!).never
          world = build_world(subqueue: 'dynflow_orchestrator:some-world-id')
          _(raw_core(world).instance_variable_get('@reply_queue')).must_equal 'dynflow_orchestrator:some-world-id'
        end
      end

      describe 'heartbeat lock reacquisition' do
        it 'reacquires the orchestrator lock when no subqueue is configured' do
          Executors::Sidekiq::Core.any_instance.stubs(:wait_for_orchestrator_lock)
          Executors::Sidekiq::Core.any_instance.stubs(:begin_startup!)
          Executors::Sidekiq::Core.any_instance.expects(:reacquire_orchestrator_lock)
          world = build_world(subqueue: nil)
          world.executor.core.ask!(:heartbeat)
        end

        it 'does not touch the lock when a subqueue is configured' do
          Executors::Sidekiq::Core.any_instance.expects(:reacquire_orchestrator_lock).never
          world = build_world(subqueue: 'dynflow_orchestrator:some-world-id')
          world.executor.core.ask!(:heartbeat)
        end
      end

      describe 'termination lock release' do
        it 'releases the orchestrator lock when no subqueue is configured' do
          Executors::Sidekiq::Core.any_instance.stubs(:wait_for_orchestrator_lock)
          Executors::Sidekiq::Core.any_instance.stubs(:begin_startup!)
          Executors::Sidekiq::Core.any_instance.expects(:release_orchestrator_lock)
          world = build_world(subqueue: nil)
          world.terminate.wait(5)
        end

        it 'does not touch the lock when a subqueue is configured' do
          Executors::Sidekiq::Core.any_instance.expects(:release_orchestrator_lock).never
          world = build_world(subqueue: 'dynflow_orchestrator:some-world-id')
          world.terminate.wait(5)
        end
      end

      describe '#feed_pool' do
        it 'tells workers to reply on the shared queue by default' do
          Executors::Sidekiq::Core.any_instance.stubs(:wait_for_orchestrator_lock)
          Executors::Sidekiq::Core.any_instance.stubs(:begin_startup!)
          world = build_world(subqueue: nil)
          work_item = stub('work_item', :queue => :default)
          proxy = mock('perform_async_proxy')
          proxy.expects(:perform_async).with(work_item, 'dynflow_orchestrator')
          Executors::Sidekiq::WorkerJobs::PerformWork.expects(:set).with(:queue => :default).returns(proxy)
          raw_core(world).feed_pool([work_item])
        end

        it 'tells workers to reply on the orchestrator-specific queue when configured' do
          reply_queue = 'dynflow_orchestrator:some-world-id'
          world = build_world(subqueue: reply_queue)
          work_item = stub('work_item', :queue => :default)
          proxy = mock('perform_async_proxy')
          proxy.expects(:perform_async).with(work_item, reply_queue)
          Executors::Sidekiq::WorkerJobs::PerformWork.expects(:set).with(:queue => :default).returns(proxy)
          raw_core(world).feed_pool([work_item])
        end
      end

      describe '#work_finished' do
        it 'processes any work unconditionally when a subqueue is configured' do
          world = build_world(subqueue: 'dynflow_orchestrator:some-world-id')
          work = stub('work', :sender_orchestrator_id => 'someone-else')
          Executors::Abstract::Core.any_instance.expects(:work_finished).with(work, nil)
          raw_core(world).work_finished(work)
        end

        it 'processes work sent by this orchestrator even without a subqueue' do
          Executors::Sidekiq::Core.any_instance.stubs(:wait_for_orchestrator_lock)
          Executors::Sidekiq::Core.any_instance.stubs(:begin_startup!)
          world = build_world(subqueue: nil)
          work = stub('work', :sender_orchestrator_id => world.id)
          Executors::Abstract::Core.any_instance.expects(:work_finished).with(work, nil)
          raw_core(world).work_finished(work)
        end

        it 'defers foreign work to handle_unknown_work_item when no subqueue is configured' do
          Executors::Sidekiq::Core.any_instance.stubs(:wait_for_orchestrator_lock)
          Executors::Sidekiq::Core.any_instance.stubs(:begin_startup!)
          world = build_world(subqueue: nil)
          core = raw_core(world)
          work = stub('work', :sender_orchestrator_id => 'someone-else')
          Executors::Abstract::Core.any_instance.expects(:work_finished).never
          core.expects(:handle_unknown_work_item).with(work)
          core.work_finished(work)
        end
      end

      describe 'drain / startup-complete recovery flow' do
        it 'begin_startup! enqueues a DrainMarker job for this world' do
          Executors::Sidekiq::Core.any_instance.stubs(:wait_for_orchestrator_lock)
          Executors::Sidekiq::WorkerJobs::DrainMarker.expects(:perform_async).with('fixed-test-world-id')
          build_world(subqueue: nil, id: 'fixed-test-world-id')
        end

        it 'DrainMarker hands off to StartupComplete for the same world id' do
          Executors::Sidekiq::OrchestratorJobs::StartupComplete.expects(:perform_async).with('some-world-id')
          Executors::Sidekiq::WorkerJobs::DrainMarker.new.perform('some-world-id')
        end

        it 'StartupComplete tells the matching orchestrator core that startup completed' do
          Executors::Sidekiq::Core.any_instance.stubs(:wait_for_orchestrator_lock)
          Executors::Sidekiq::Core.any_instance.stubs(:begin_startup!)
          world = build_world(subqueue: nil)
          world.executor.core.expects(:tell).with([:startup_complete])
          Executors::Sidekiq::OrchestratorJobs::StartupComplete.new.perform(world.id)
        end

        it 'StartupComplete discards notifications meant for a different world' do
          Executors::Sidekiq::Core.any_instance.stubs(:wait_for_orchestrator_lock)
          Executors::Sidekiq::Core.any_instance.stubs(:begin_startup!)
          world = build_world(subqueue: nil)
          world.executor.core.expects(:tell).never
          Executors::Sidekiq::OrchestratorJobs::StartupComplete.new.perform('a-different-world-id')
        end

        it '#startup_complete runs validity checks and clears recovery mode' do
          Executors::Sidekiq::Core.any_instance.stubs(:wait_for_orchestrator_lock)
          Executors::Sidekiq::Core.any_instance.stubs(:begin_startup!)
          world = build_world(subqueue: nil)
          core = raw_core(world)
          core.instance_variable_set('@recovery', true)
          world.expects(:perform_validity_checks)
          core.startup_complete
          _(core.instance_variable_get('@recovery')).must_equal false
        end
      end
    end
  end
end
