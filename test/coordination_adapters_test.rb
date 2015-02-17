require_relative 'test_helper'
require 'fileutils'

module Dynflow
  module CoordinationAdaptersTest
    describe CoordinationAdapters do
      let(:world)         { WorldFactory.create_world }
      let(:another_world) { WorldFactory.create_world }

      def self.it_supports_locking
        describe 'locking' do
          it 'prevents acquiring a lock while there is the same id already taken' do
            begin
              lock_request = CoordinationAdapters::ConsistencyCheckLock.new
              tester = ConcurrentRunTester.new
              tester.while_executing do
                adapter.lock(lock_request)
                tester.pause
              end
              -> { another_adapter.lock(lock_request) }.must_raise(Errors::LockError)
              tester.finish
            ensure
              adapter.unlock(lock_request)
            end
          end

          it 'allows acquiring different types of locks' do
            begin
              lock_request = CoordinationAdapters::ConsistencyCheckLock.new
              another_lock_request = CoordinationAdapters::WorldInvalidationLock.new(world)
              tester = ConcurrentRunTester.new
              tester.while_executing do
                adapter.lock(lock_request)
                tester.pause
              end
              another_adapter.lock(another_lock_request) # expected no error raised
              tester.finish
            ensure
              adapter.unlock(lock_request)
              another_adapter.unlock(another_lock_request)
            end
          end

          it 'allows unlocking all locks acquired by some world' do
            begin
              lock_request = CoordinationAdapters::ConsistencyCheckLock.new
              tester = ConcurrentRunTester.new
              tester.while_executing do
                adapter.lock(lock_request)
                tester.pause
              end
              another_adapter.unlock_all(world.id)
              another_adapter.lock(lock_request) # expected no error raised
              tester.finish
            ensure
              another_adapter.unlock(lock_request)
            end
          end
        end
      end

      describe CoordinationAdapters::Sequel do
        let(:adapter) { CoordinationAdapters::Sequel.new(world) }
        let(:another_adapter) { CoordinationAdapters::Sequel.new(another_world) }
        it_supports_locking
      end
    end
  end
end
