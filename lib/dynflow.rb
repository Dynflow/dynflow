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

  class Error < StandardError
    def to_hash
      { class: self.class.name, message: message, backtrace: backtrace }
    end

    def self.from_hash(hash)
      self.new(hash[:message]).tap { |e| e.set_backtrace(hash[:backtrace]) }
    end
  end

  require 'dynflow/utils'
  require 'dynflow/round_robin'
  require 'dynflow/dead_letter_silencer'
  require 'dynflow/actor'
  require 'dynflow/actors'
  require 'dynflow/errors'
  require 'dynflow/serializer'
  require 'dynflow/serializable'
  require 'dynflow/clock'
  require 'dynflow/stateful'
  require 'dynflow/transaction_adapters'
  require 'dynflow/coordinator'
  require 'dynflow/persistence'
  require 'dynflow/middleware'
  require 'dynflow/flows'
  require 'dynflow/execution_history'
  require 'dynflow/execution_plan'
  require 'dynflow/delayed_plan'
  require 'dynflow/action'
  require 'dynflow/director'
  require 'dynflow/executors'
  require 'dynflow/logger_adapters'
  require 'dynflow/world'
  require 'dynflow/connectors'
  require 'dynflow/dispatcher'
  require 'dynflow/serializers'
  require 'dynflow/delayed_executors'
  require 'dynflow/semaphores'
  require 'dynflow/throttle_limiter'
  require 'dynflow/telemetry'
  require 'dynflow/config'

  if defined? ::ActiveJob
    require 'dynflow/active_job/queue_adapter'

    class Railtie < Rails::Railtie
      config.before_initialize do
        ::ActiveJob::QueueAdapters.send(
          :include,
          Dynflow::ActiveJob::QueueAdapters
        )
      end
    end
  end

  if defined? Rails
    require 'dynflow/rails'
  end
end
