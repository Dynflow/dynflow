require_relative 'test_helper'
require 'fileutils'

module Dynflow
  module CoordinatorTest
    describe Coordinator do
      let(:world)         { WorldFactory.create_world }
      let(:another_world) { WorldFactory.create_world }

      describe 'locks' do
        it 'unlocks the lock, when the block is passed' do
          world.coordinator.acquire(Coordinator::ConsistencyCheckLock.new(world)) {}
          expected_locks = ["lock consistency-check", "unlock consistency-check"]
          world.coordinator.adapter.lock_log.must_equal(expected_locks)
        end

        it "doesn't unlock, when the block is not passed" do
          world.coordinator.acquire(Coordinator::ConsistencyCheckLock.new(world))
          expected_locks = ["lock consistency-check"]
          world.coordinator.adapter.lock_log.must_equal(expected_locks)
        end
      end

      describe 'on termination' do
        it 'removes all the locks assigned to the given world' do
          world.coordinator.acquire(Coordinator::ConsistencyCheckLock.new(world))
          world.terminate.wait
          expected_locks = ["lock consistency-check", "unlock all for owner world:#{world.id}"]
          world.coordinator.adapter.lock_log.must_equal(expected_locks)
        end

        it 'prevents new locks to be acquired by the world being terminated' do
          world.terminate
          -> do
            world.coordinator.acquire(Coordinator::ConsistencyCheckLock.new(world))
          end.must_raise(Errors::InactiveWorldError)
        end

        it ' deserializes the data from the adapter when searching for locks' do
          lock = Coordinator::ConsistencyCheckLock.new(world)
          world.coordinator.acquire(lock)
          found_locks = world.coordinator.find_locks(owner_id: lock.owner_id)
          found_locks.size.must_equal 1
          found_locks.first.data.must_equal lock.data

          found_locks = world.coordinator.find_locks(class: lock.class.name, id: lock.id)
          found_locks.size.must_equal 1
          found_locks.first.data.must_equal lock.data

          another_lock = Coordinator::ConsistencyCheckLock.new(another_world)
          found_locks = world.coordinator.find_locks(owner_id: another_lock.owner_id)
          found_locks.size.must_equal 0
        end
      end

      def self.it_supports_locking
        describe 'locking' do
          it 'prevents acquiring a lock while there is the same id already taken' do
            lock = Coordinator::ConsistencyCheckLock.new(world)
            tester = ConcurrentRunTester.new
            tester.while_executing do
              adapter.acquire(lock)
              tester.pause
            end
            -> { another_adapter.acquire(lock) }.must_raise(Errors::LockError)
            tester.finish
          end

          it 'allows acquiring different types of locks' do
            lock = Coordinator::ConsistencyCheckLock.new(world)
            another_lock = Coordinator::WorldInvalidationLock.new(world, another_world)
            tester = ConcurrentRunTester.new
            tester.while_executing do
              adapter.acquire(lock)
              tester.pause
            end
            another_adapter.acquire(another_lock) # expected no error raised
            tester.finish
          end

          it 'allows unlocking all locks acquired by some world' do
            lock = Coordinator::ConsistencyCheckLock.new(world)
            tester = ConcurrentRunTester.new
            tester.while_executing do
              adapter.acquire(lock)
              tester.pause
            end
            another_adapter.release_by_owner(Coordinator::LockByWorld.new(world).owner_id)
            another_adapter.acquire(lock) # expected no error raised
            tester.finish
          end

          it 'allows searching for the locks on various criteria' do
            lock = Coordinator::ConsistencyCheckLock.new(world)
            adapter.acquire(lock)
            found_locks = adapter.find_locks(owner_id: lock.owner_id)
            found_locks.size.must_equal 1
            found_locks.first.must_equal lock.data

            found_locks = adapter.find_locks(class: lock.class.name, id: lock.id)
            found_locks.size.must_equal 1
            found_locks.first.must_equal lock.data

            another_lock = Coordinator::ConsistencyCheckLock.new(another_world)
            found_locks = adapter.find_locks(owner_id: another_lock.owner_id)
            found_locks.size.must_equal 0
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
