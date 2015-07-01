# -*- coding: utf-8 -*-
require_relative 'test_helper'

module Dynflow
  module RoundRobinTest
    describe RoundRobin do
      let(:rr) { Dynflow::RoundRobin.new }
      specify do
        rr.next.must_be_nil
        rr.next.must_be_nil
        rr.must_be_empty
        rr.add 1
        rr.next.must_equal 1
        rr.next.must_equal 1
        rr.add 2
        rr.next.must_equal 2
        rr.next.must_equal 1
        rr.next.must_equal 2
        rr.delete 1
        rr.next.must_equal 2
        rr.next.must_equal 2
        rr.delete 2
        rr.next.must_be_nil
        rr.must_be_empty
      end
    end
  end
end
