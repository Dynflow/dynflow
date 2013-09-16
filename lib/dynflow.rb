require 'apipie-params'
require 'algebrick'
require 'thread'
require 'set'
require 'active_support/core_ext/hash/indifferent_access'


# TODO model locking in plan phase, releasing after run in finalize
# TODO RemoteExecutor and Daemon process to pick the work up
# TODO validate in/output, also validate unknown keys
# FIND also execute planning phase in workers to be consistent, args serialization? :/
module Dynflow

  require 'dynflow/future'
  require 'dynflow/serializable'
  require 'dynflow/transaction_adapters'
  require 'dynflow/persistence'
  require 'dynflow/action'
  require 'dynflow/flows'
  require 'dynflow/execution_plan'
  require 'dynflow/executors'
  require 'dynflow/world'
  require 'dynflow/simple_world'

end


# FIND a state-machine gem? for state transitions in Step and EP
