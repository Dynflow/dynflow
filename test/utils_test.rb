# frozen_string_literal: true
require_relative 'test_helper'

module Dynflow
  module UtilsTest
    describe ::Dynflow::Utils::PriorityQueue do
      let(:queue) { Utils::PriorityQueue.new }

      it 'can insert elements' do
        queue.push 1
        queue.top.must_equal 1
        queue.push 2
        queue.top.must_equal 2
        queue.push 3
        queue.top.must_equal 3
        queue.to_a.must_equal [1, 2, 3]
      end

      it 'can override the comparator' do
        queue = Utils::PriorityQueue.new { |a, b| b <=> a }
        queue.push 1
        queue.top.must_equal 1
        queue.push 2
        queue.top.must_equal 1
        queue.push 3
        queue.top.must_equal 1
        queue.to_a.must_equal [3, 2, 1]
      end

      it 'can inspect top element without removing it' do
        queue.top.must_be_nil
        queue.push(1)
        queue.top.must_equal 1
        queue.push(3)
        queue.top.must_equal 3
        queue.push(2)
        queue.top.must_equal 3
      end

      it 'can report size' do
        count = 5
        count.times { queue.push 1 }
        queue.size.must_equal count
      end

      it 'pops elements in correct order' do
        queue.push 1
        queue.push 3
        queue.push 2
        queue.pop.must_equal 3
        queue.pop.must_equal 2
        queue.pop.must_equal 1
        queue.pop.must_equal nil
      end
    end
  end
end
