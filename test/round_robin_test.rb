# -*- coding: utf-8 -*-
# frozen_string_literal: true
require_relative 'test_helper'

module Dynflow
  module RoundRobinTest
    describe RoundRobin do
      let(:rr) { Dynflow::RoundRobin.new }
      specify do
        assert_nil rr.next
        assert_nil rr.next
        _(rr).must_be_empty
        rr.add 1
        _(rr.next).must_equal 1
        _(rr.next).must_equal 1
        rr.add 2
        _(rr.next).must_equal 2
        _(rr.next).must_equal 1
        _(rr.next).must_equal 2
        rr.delete 1
        _(rr.next).must_equal 2
        _(rr.next).must_equal 2
        rr.delete 2
        assert_nil rr.next
        _(rr).must_be_empty
      end
    end
  end
end
