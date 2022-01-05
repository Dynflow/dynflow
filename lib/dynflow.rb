# frozen_string_literal: true
require 'apipie-params'
require 'algebrick'
require 'thread'
require 'set'
require 'base64'
require 'concurrent'
require 'concurrent-edge'

logger                          = Logger.new($stderr)
logger.level                    = Logger::INFO
Concurrent.global_logger = lambda do |level, progname, message = nil, &block|
  logger.add level, message, progname, &block
end

# TODO validate in/output, also validate unknown keys
# TODO performance testing, how many actions will it handle?
# TODO profiling, find bottlenecks
# FIND change ids to uuid, uuid-<action_id>, uuid-<action_id-(plan, run, finalize)
module Dynflow
  class << self
    # Return the world that representing this process - this is mainly used by
    # Sidekiq deployments, where there is a need for a global-level context.
    #
    # @return [Dynflow::World, nil]
    def process_world
      return @process_world if defined? @process_world
      @process_world = Sidekiq.options[:dynflow_world]
      raise "process world is not set" unless @process_world
      @process_world
    end
  end

  if defined? ::ActiveJob
    require 'dynflow/active_job'
    class Railtie < ::Rails::Railtie
      config.before_initialize do
        ::ActiveJob::QueueAdapters.send(
          :include,
          Dynflow::ActiveJob::QueueAdapters
        )
      end
    end
  end

  if defined? ::Rails
    loader = Zeitwerk::Loader.new
    loader.push_dir("#{__dir__}/dynflow/rails", namespace: ::Dynflow::Rails)
    loader.setup
    loader.eager_load
  end
end

require 'zeitwerk'
loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect('statsd' => 'StatsD')
loader.inflector.inflect('msgpack' => 'MsgPack')
loader.ignore("#{__dir__}/dynflow/persistence_adapters/sequel_migrations")
loader.ignore("#{__dir__}/dynflow/executors/sidekiq")
loader.ignore("#{__dir__}/dynflow/executors/sidekiq.rb")
loader.ignore("#{__dir__}/dynflow/active_job.rb")
loader.ignore("#{__dir__}/dynflow/active_job")
loader.ignore("#{__dir__}/dynflow/rails")
loader.setup
loader.eager_load
