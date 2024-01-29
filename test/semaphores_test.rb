# frozen_string_literal: true

require_relative 'test_helper'

module Dynflow
  module SemaphoresTest
    describe ::Dynflow::Semaphores::Stateful do
      let(:semaphore_class) { ::Dynflow::Semaphores::Stateful }
      let(:tickets_count) { 5 }

      it 'can be used as counter' do
        expected_state = { :tickets => tickets_count, :free => 4, :meta => {} }
        semaphore = semaphore_class.new(tickets_count)
        _(semaphore.tickets).must_equal tickets_count
        _(semaphore.free).must_equal tickets_count
        _(semaphore.waiting).must_be_empty
        _(semaphore.get).must_equal 1
        _(semaphore.free).must_equal tickets_count - 1
        _(semaphore.get(3)).must_equal 3
        _(semaphore.free).must_equal tickets_count - (3 + 1)
        _(semaphore.drain).must_equal 1
        _(semaphore.free).must_equal tickets_count - (3 + 1 + 1)
        semaphore.release
        _(semaphore.free).must_equal tickets_count - (3 + 1)
        semaphore.release 3
        _(semaphore.free).must_equal tickets_count - 1
        _(semaphore.to_hash).must_equal expected_state
      end

      it 'can have things waiting on it' do
        semaphore = semaphore_class.new 1
        allowed = semaphore.wait(1)
        _(allowed).must_equal true
        _(semaphore.free).must_equal 0
        allowed = semaphore.wait(2)
        _(allowed).must_equal false
        allowed = semaphore.wait(3)
        _(allowed).must_equal false
        waiting = semaphore.get_waiting
        _(waiting).must_equal 2
        waiting = semaphore.get_waiting
        _(waiting).must_equal 3
      end
    end

    describe ::Dynflow::Semaphores::Dummy do
      let(:semaphore_class) { ::Dynflow::Semaphores::Dummy }

      it 'always has free' do
        semaphore = semaphore_class.new
        _(semaphore.free).must_equal 1
        _(semaphore.get(5)).must_equal 5
        _(semaphore.free).must_equal 1
      end

      it 'cannot have things waiting on it' do
        semaphore = semaphore_class.new
        _(semaphore.wait(1)).must_equal true
        _(semaphore.has_waiting?).must_equal false
      end
    end

    describe ::Dynflow::Semaphores::Aggregating do
      let(:semaphore_class) { ::Dynflow::Semaphores::Aggregating }
      let(:child_class) { ::Dynflow::Semaphores::Stateful }
      let(:children) do
        {
          :child_A => child_class.new(3),
          :child_B => child_class.new(2)
        }
      end

      def assert_semaphore_state(semaphore, state_a, state_b)
        _(semaphore.children[:child_A].free).must_equal state_a
        _(semaphore.children[:child_B].free).must_equal state_b
        _(semaphore.free).must_equal [state_a, state_b].min
      end

      it 'can be used as counter' do
        semaphore = semaphore_class.new(children)
        assert_semaphore_state semaphore, 3, 2
        _(semaphore.get).must_equal 1
        assert_semaphore_state semaphore, 2, 1
        _(semaphore.get).must_equal 1
        assert_semaphore_state semaphore, 1, 0
        _(semaphore.get).must_equal 0
        assert_semaphore_state semaphore, 1, 0
        semaphore.release
        assert_semaphore_state semaphore, 2, 1
        semaphore.release(1, :child_B)
        assert_semaphore_state semaphore, 2, 2
        _(semaphore.drain).must_equal 2
        assert_semaphore_state semaphore, 0, 0
      end
    end

  end
end
