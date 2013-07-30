require 'apipie-params'
require 'algebrick'
require 'thread'
require 'set'
require 'active_support/core_ext/hash/indifferent_access'

module Dynflow

  require 'dynflow/future'
  require 'dynflow/serializable'
  require 'dynflow/transaction_adapters'
  require 'dynflow/persistence'
  require 'dynflow/executors'
  require 'dynflow/action'
  require 'dynflow/flows'
  require 'dynflow/execution_plan'
  require 'dynflow/world'
  require 'dynflow/simple_world'

  module Dedent
    def dedent(string)
      dedent = string.scan(/^ */).map { |spaces| spaces.size }.min
      string.lines.map { |line| line[dedent..-1] }.join
    end
  end
end
