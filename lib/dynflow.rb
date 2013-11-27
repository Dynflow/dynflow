require 'apipie-params'
require 'algebrick'
require 'thread'
require 'set'
require 'active_support/core_ext/hash/indifferent_access'

# FIXME contocurency errors in tests
# - recovery after restart is not implemented
# - log writing failed. KeyError
# TODO model locking in plan phase, releasing after run in finalize
# TODO validate in/output, also validate unknown keys
# FIND also execute planning phase in workers to be consistent, args serialization? :/
module Dynflow

  class Error < StandardError
  end

  require 'dynflow/future'
  require 'dynflow/micro_actor'
  require 'dynflow/serializable'
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

class Logger
  class LogDevice
    def write(message)
      begin
        @mutex.synchronize do
          if @shift_age and @dev.respond_to?(:stat)
            begin
              check_shift_log
            rescue
              warn("log shifting failed. #{$!}")
            end
          end
          begin
            @dev.write(message)
          rescue => ignored
            warn "#{ignored.message} (#{ignored.class})\n#{ignored.backtrace.join("\n")}"
            warn("log writing failed. #{$!}")
          end
        end
      rescue Exception => ignored
        warn "#{ignored.message} (#{ignored.class})\n#{ignored.backtrace.join("\n")}"
        warn("log writing failed. #{ignored}")
      end
    end

  end
end
