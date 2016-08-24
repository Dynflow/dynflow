require_relative 'test_helper'

module Dynflow
  module SemaphoresTest
    describe ::Dynflow::Semaphores::Stateful do

      let(:semaphore_class) { ::Dynflow::Semaphores::Stateful }
      let(:tickets_count) { 5 }

      it 'can be used as counter' do
        expected_state = { :tickets => tickets_count, :free => 4, :meta => {} }
        semaphore = semaphore_class.new(tickets_count)
        semaphore.tickets.must_equal tickets_count
        semaphore.free.must_equal tickets_count
        semaphore.waiting.must_be_empty
        semaphore.get.must_equal 1
        semaphore.free.must_equal tickets_count - 1
        semaphore.get(3).must_equal 3
        semaphore.free.must_equal tickets_count - (3 + 1)
        semaphore.drain.must_equal 1
        semaphore.free.must_equal tickets_count - (3 + 1 + 1)
        semaphore.release
        semaphore.free.must_equal tickets_count - (3 + 1)
        semaphore.release 3
        semaphore.free.must_equal tickets_count - 1
        semaphore.to_hash.must_equal expected_state
      end

      it 'can have things waiting on it' do
        semaphore = semaphore_class.new 1
        allowed = semaphore.wait(1)
        allowed.must_equal true
        semaphore.free.must_equal 0
        allowed = semaphore.wait(2)
        allowed.must_equal false
        allowed = semaphore.wait(3)
        allowed.must_equal false
        waiting = semaphore.get_waiting
        waiting.must_equal 2
        waiting = semaphore.get_waiting
        waiting.must_equal 3
      end

    end

    describe ::Dynflow::Semaphores::Dummy do
      let(:semaphore_class) { ::Dynflow::Semaphores::Dummy }

      it 'always has free' do
        semaphore = semaphore_class.new
        semaphore.free.must_equal 1
        semaphore.get(5).must_equal 5
        semaphore.free.must_equal 1
      end

      it 'cannot have things waiting on it' do
        semaphore = semaphore_class.new
        semaphore.wait(1).must_equal true
        semaphore.has_waiting?.must_equal false
      end
    end

    describe ::Dynflow::Semaphores::Aggregating do
      let(:klass) { ::Dynflow::Semaphores::Aggregating }
      let(:child_class) { ::Dynflow::Semaphores::Stateful }
      let(:children) do
        {
          :child_A => child_class.new(3),
          :child_B => child_class.new(2)
        }
      end

      def assert_semaphore_state(semaphore, state_A, state_B)
        semaphore.children[:child_A].free.must_equal state_A
        semaphore.children[:child_B].free.must_equal state_B
        semaphore.free.must_equal [state_A, state_B].min
      end

      it 'can be used as counter' do
        semaphore = klass.new(children)
        assert_semaphore_state semaphore, 3, 2
        semaphore.get.must_equal 1
        assert_semaphore_state semaphore, 2, 1
        semaphore.get.must_equal 1
        assert_semaphore_state semaphore, 1, 0
        semaphore.get.must_equal 0
        assert_semaphore_state semaphore, 1, 0
        semaphore.release
        assert_semaphore_state semaphore, 2, 1
        semaphore.release(1, :child_B)
        assert_semaphore_state semaphore, 2, 2
        semaphore.drain.must_equal 2
        assert_semaphore_state semaphore, 0, 0
      end
    end

  end
end
