require_relative 'test_helper'
require 'logger'

clock_class = Dynflow::Clock

describe clock_class do

  let(:clock) { clock_class.spawn 'clock' }

  it 'refuses who without #<< method' do
    -> { clock.ping Object.new, 0.1, :pong }.must_raise TypeError
    clock.ping [], 0.1, :pong
  end

  it 'pongs' do
    q = Queue.new
    start = Time.now

    clock.ping q, 0.1, o = Object.new
    assert_equal o, q.pop
    finish = Time.now
    assert_in_delta 0.1, finish - start, 0.08
  end

  it 'pongs on expected times' do
    q = Queue.new
    start = Time.now

    clock.ping q, 0.3, :a
    clock.ping q, 0.1, :b
    clock.ping q, 0.2, :c

    assert_equal :b, q.pop
    assert_in_delta 0.1, Time.now - start, 0.08
    assert_equal :c, q.pop
    assert_in_delta 0.2, Time.now - start, 0.08
    assert_equal :a, q.pop
    assert_in_delta 0.3, Time.now - start, 0.08
  end

  it 'works under stress' do
    threads = Array.new(4) do
      Thread.new do
        q     = Queue.new
        times = 20
        times.times { |i| clock.ping q, rand, i }
        assert_equal (0...times).to_a, Array.new(times) { q.pop }.sort
      end
    end
    threads.each &:join
  end

end
