require_relative 'test_helper'
require 'fileutils'

module Dynflow
  module CoordinatorTest
    describe Coordinator do
      let(:world)         { WorldFactory.create_world }
      let(:another_world) { WorldFactory.create_world }

      describe '#lock' do
        it 'unlocks the lock, when the block is passed' do
          world.coordinator.lock(Coordinator::ConsistencyCheckLock.new) {}
          expected_locks = ["lock consistency-check", "unlock consistency-check"]
          world.coordinator.adapter.lock_log.must_equal(expected_locks)
        end

        it "doesn't unlock, when the block is not passed" do
          world.coordinator.lock(Coordinator::ConsistencyCheckLock.new)
          expected_locks = ["lock consistency-check"]
          world.coordinator.adapter.lock_log.must_equal(expected_locks)
        end
      end

      describe 'on termination' do
        it 'removes all the locks assigned to the given world' do
          world.coordinator.lock(Coordinator::ConsistencyCheckLock.new)
          world.terminate.wait
          expected_locks = ["lock consistency-check", "unlock all for world #{world.id}"]
          world.coordinator.adapter.lock_log.must_equal(expected_locks)
        end

        it 'prevents new locks to be acquired by the world being terminated' do
          world.terminate
          -> do
            world.coordinator.lock(Coordinator::ConsistencyCheckLock.new)
          end.must_raise(Errors::InactiveWorldError)
        end
      end

      def self.it_supports_locking
        describe 'locking' do
          it 'prevents acquiring a lock while there is the same id already taken' do
            lock_request = Coordinator::ConsistencyCheckLock.new
            tester = ConcurrentRunTester.new
            tester.while_executing do
              adapter.lock(lock_request)
              tester.pause
            end
            -> { another_adapter.lock(lock_request) }.must_raise(Errors::LockError)
            tester.finish
          end

          it 'allows acquiring different types of locks' do
            lock_request = Coordinator::ConsistencyCheckLock.new
            another_lock_request = Coordinator::WorldInvalidationLock.new(world)
            tester = ConcurrentRunTester.new
            tester.while_executing do
              adapter.lock(lock_request)
              tester.pause
            end
            another_adapter.lock(another_lock_request) # expected no error raised
            tester.finish
          end

          it 'allows unlocking all locks acquired by some world' do
            lock_request = Coordinator::ConsistencyCheckLock.new
            tester = ConcurrentRunTester.new
            tester.while_executing do
              adapter.lock(lock_request)
              tester.pause
            end
            another_adapter.unlock_all(world.id)
            another_adapter.lock(lock_request) # expected no error raised
            tester.finish
          end
        end
      end

      describe CoordinatorAdapters::Sequel do
        let(:adapter) { CoordinatorAdapters::Sequel.new(world) }
        let(:another_adapter) { CoordinatorAdapters::Sequel.new(another_world) }
        it_supports_locking
      end
    end
  end
end
