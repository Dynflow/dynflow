require 'apipie-params'
require 'algebrick'
require 'thread'
require 'set'
require 'base64'
require 'concurrent'
require 'concurrent-edge'
require 'active_job'

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
    # Return the orchestrator world that is representing this process - it's assumed there
    # will be only orchestrator present in the deployment.
    #
    # Multiple orchestrators could be achieved by introducing multiple orchestrator queues
    # with a smart connector that would know to what queue distribute the messages, based
    # on the content
    #
    # @return [Dynflow::World, nil]
    def orchestrator
      @orchestrator
    end

    def orchestrator=(orchestrator)
      raise "orchestrator is already set" if @orchestrator
      @orchestrator = orchestrator
    end

    def orchestrator_reset
      @orchestrator = nil
    end
  end

  class Error < StandardError
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

  if defined? Rails
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
