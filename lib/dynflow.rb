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

  class Error < StandardError
  end

  require 'dynflow/utils'
  require 'dynflow/round_robin'
  require 'dynflow/actor'
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
  require 'dynflow/config'
  require 'dynflow/exporters'
end
