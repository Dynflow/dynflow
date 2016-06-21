require_relative 'test_helper'
require 'fileutils'

module Dynflow
  module CoordinatorTest
    describe Coordinator do
      let(:world)         { WorldFactory.create_world }
      let(:another_world) { WorldFactory.create_world }

      describe 'locks' do
        it 'unlocks the lock, when the block is passed' do
          world.coordinator.acquire(Coordinator::AutoExecuteLock.new(world)) {}
          expected_locks = ["lock auto-execute", "unlock auto-execute"]
          world.coordinator.adapter.lock_log.must_equal(expected_locks)
        end

        it "doesn't unlock, when the block is not passed" do
          world.coordinator.acquire(Coordinator::AutoExecuteLock.new(world))
          expected_locks = ["lock auto-execute"]
          world.coordinator.adapter.lock_log.must_equal(expected_locks)
        end

        it 'supports unlocking by owner' do
          lock = Coordinator::AutoExecuteLock.new(world)
          tester = ConcurrentRunTester.new
          tester.while_executing do
            world.coordinator.acquire(lock)
            tester.pause
          end
          world.coordinator.release_by_owner("world:#{world.id}")
          world.coordinator.acquire(lock) # expected no error raised
          tester.finish
        end

        it 'supports checking about locks' do
          world.coordinator.acquire(Coordinator::AutoExecuteLock.new(world))
          locks = world.coordinator.find_locks(Coordinator::AutoExecuteLock.unique_filter)
          locks.map(&:world_id).must_equal([world.id])
        end

        it 'deserializes the data from the adapter when searching for locks' do
          lock = Coordinator::AutoExecuteLock.new(world)
          world.coordinator.acquire(lock)
          found_locks = world.coordinator.find_locks(owner_id: lock.owner_id)
          found_locks.size.must_equal 1
          found_locks.first.data.must_equal lock.data

          found_locks = world.coordinator.find_locks(class: lock.class.name, id: lock.id)
          found_locks.size.must_equal 1
          found_locks.first.data.must_equal lock.data

          another_lock = Coordinator::AutoExecuteLock.new(another_world)
          found_locks = world.coordinator.find_locks(owner_id: another_lock.owner_id)
          found_locks.size.must_equal 0
        end
      end

      describe 'records' do
        class DummyRecord < Coordinator::Record
          def initialize(id, value)
            super
            @data[:id] = value
            @data[:value] = value
          end

          def value
            @data[:value]
          end

          def value=(value)
            @data[:value] = (value)
          end
        end

        it 'allows CRUD record objects' do
          dummy_record = DummyRecord.new('dummy', 'Foo')
          world.coordinator.create_record(dummy_record)
          saved_dummy_record = world.coordinator.find_records(class: dummy_record.class.name).first
          saved_dummy_record.must_equal dummy_record

          dummy_record.value = 'Bar'
          world.coordinator.update_record(dummy_record)
          saved_dummy_record = world.coordinator.find_records(class: dummy_record.class.name).first
          saved_dummy_record.data.must_equal dummy_record.data

          world.coordinator.delete_record(dummy_record)
          world.coordinator.find_records(class: dummy_record.class.name).must_equal []
        end
      end

      describe 'on termination' do
        it 'removes all the locks assigned to the given world' do
          world.coordinator.acquire(Coordinator::AutoExecuteLock.new(world))
          another_world.coordinator.acquire Coordinator::WorldInvalidationLock.new(another_world, another_world)
          world.terminate.wait
          expected_locks = ["lock auto-execute", "unlock auto-execute"]
          world.coordinator.adapter.lock_log.must_equal(expected_locks)
        end

        it 'prevents new locks to be acquired by the world being terminated' do
          world.terminate
          -> do
            world.coordinator.acquire(Coordinator::AutoExecuteLock.new(world))
          end.must_raise(Errors::InactiveWorldError)
        end
      end

      def self.it_supports_global_records
        describe 'records handling' do
          it 'prevents saving the same record twice' do
            record = Coordinator::AutoExecuteLock.new(world)
            tester = ConcurrentRunTester.new
            tester.while_executing do
              adapter.create_record(record)
              tester.pause
            end
            -> { another_adapter.create_record(record) }.must_raise(Coordinator::DuplicateRecordError)
            tester.finish
          end

          it 'allows saving different records' do
            record = Coordinator::AutoExecuteLock.new(world)
            another_record = Coordinator::WorldInvalidationLock.new(world, another_world)
            tester = ConcurrentRunTester.new
            tester.while_executing do
              adapter.create_record(record)
              tester.pause
            end
            another_adapter.create_record(another_record) # expected no error raised
            tester.finish
          end

          it 'allows searching for the records on various criteria' do
            lock = Coordinator::AutoExecuteLock.new(world)
            adapter.create_record(lock)
            found_records = adapter.find_records(owner_id: lock.owner_id)
            found_records.size.must_equal 1
            found_records.first.must_equal lock.data

            found_records = adapter.find_records(class: lock.class.name, id: lock.id)
            found_records.size.must_equal 1
            found_records.first.must_equal lock.data

            another_lock = Coordinator::AutoExecuteLock.new(another_world)
            found_records = adapter.find_records(owner_id: another_lock.owner_id)
            found_records.size.must_equal 0
          end
        end
      end

      describe CoordinatorAdapters::Sequel do
        let(:adapter) { CoordinatorAdapters::Sequel.new(world) }
        let(:another_adapter) { CoordinatorAdapters::Sequel.new(another_world) }
        it_supports_global_records
      end
    end
  end
end
