require 'apipie-params'
require 'algebrick'
require 'thread'
require 'set'
require 'active_support/core_ext/hash/indifferent_access'

# TODO validate in/output, also validate unknown keys
# TODO performance testing, how many actions will it handle?
# TODO profiling, find bottlenecks
# FIND also execute planning phase in workers to be consistent, execute in remote executors to avoid serialization
module Dynflow

  class Error < StandardError
  end

  require 'dynflow/future'
  require 'dynflow/micro_actor'
  require 'dynflow/serializable'
  require 'dynflow/clock'
  require 'dynflow/stateful'
  require 'dynflow/transaction_adapters'
  require 'dynflow/persistence'
  require 'dynflow/action'
  require 'dynflow/flows'
  require 'dynflow/execution_plan'
  require 'dynflow/listeners'
  require 'dynflow/executors'
  require 'dynflow/logger_adapters'
  require 'dynflow/world'
  require 'dynflow/simple_world'
  require 'dynflow/daemon'

end
