require 'apipie-params'
require 'algebrick'
require 'thread'
require 'set'
require 'active_support/core_ext/hash/indifferent_access'


# TODO model locking in plan phase, releasing after run in finalize
# TODO validate in/output, also validate unknown keys
# FIND also execute planning phase in workers to be consistent, args serialization? :/
module Dynflow

  class Error < StandardError
  end

  require 'dynflow/future'
  require 'dynflow/serializable'
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


# FIND a state-machine gem? for state transitions in Step and EP
