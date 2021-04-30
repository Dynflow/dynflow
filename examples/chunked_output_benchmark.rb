#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'example_helper'
require 'benchmark'

WORDS = File.readlines('/usr/share/dict/words').map(&:chomp).freeze
COUNT = WORDS.count

module Common
  def main_loop
    if output[:current] < input[:limit]
      consumed = yield
      output[:current] += consumed
      plan_event(nil)
      suspend
    end
  end

  def batch
    WORDS.drop(output[:current]).take(input[:chunk])
  end
end

class Regular < ::Dynflow::Action
  include Common

  def run(event = nil)
    output[:current] ||= 0
    output[:words] ||= []

    main_loop do
      words = batch
      output[:words] << words
      words.count
    end
  end
end

class Chunked < ::Dynflow::Action
  include Common

  def run(event = nil)
    output[:current] ||= 0

    main_loop do
      words = batch
      output_chunk(words)
      words.count
    end
  end
end

if $0 == __FILE__
  ExampleHelper.world.action_logger.level = 4
  ExampleHelper.world.logger.level = 4

  Benchmark.bm do |bm|
    bm.report('regular    1000 by    100') { ExampleHelper.world.trigger(Regular, limit: 1000, chunk: 100).finished.wait }
    bm.report('chunked    1000 by    100') { ExampleHelper.world.trigger(Chunked, limit: 1000, chunk: 100).finished.wait }

    bm.report('regular  10_000 by    100') { ExampleHelper.world.trigger(Regular, limit: 10_000, chunk: 100).finished.wait }
    bm.report('chunked  10_000 by    100') { ExampleHelper.world.trigger(Chunked, limit: 10_000, chunk: 100).finished.wait }

    bm.report('regular  10_000 by   1000') { ExampleHelper.world.trigger(Regular, limit: 10_000, chunk: 1000).finished.wait }
    bm.report('chunked  10_000 by   1000') { ExampleHelper.world.trigger(Chunked, limit: 10_000, chunk: 1000).finished.wait }

    bm.report('regular 100_000 by    100') { ExampleHelper.world.trigger(Regular, limit: 100_000, chunk: 100).finished.wait }
    bm.report('chunked 100_000 by    100') { ExampleHelper.world.trigger(Chunked, limit: 100_000, chunk: 100).finished.wait }

    bm.report('regular 100_000 by   1000') { ExampleHelper.world.trigger(Regular, limit: 100_000, chunk: 1000).finished.wait }
    bm.report('chunked 100_000 by   1000') { ExampleHelper.world.trigger(Chunked, limit: 100_000, chunk: 1000).finished.wait }

    bm.report('regular 100_000 by 10_000') { ExampleHelper.world.trigger(Regular, limit: 100_000, chunk: 10_000).finished.wait }
    bm.report('chunked 100_000 by 10_000') { ExampleHelper.world.trigger(Chunked, limit: 100_000, chunk: 10_000).finished.wait }
  end
end
