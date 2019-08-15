# frozen_string_literal: true
module Dynflow
  module Executors

    require 'dynflow/executors/parallel'

    # Every time we run a code that can be defined outside of Dynflow,
    # we should wrap it with this method, and we can ensure here to do
    # necessary cleanup, such as cleaning ActiveRecord connections
    def self.run_user_code
      clear_connections = defined?(::ActiveRecord) && ActiveRecord::Base.connected? && ActiveRecord::Base.connection.open_transactions.zero?
      yield
    ensure
      ::ActiveRecord::Base.clear_active_connections! if clear_connections
      ::Logging.mdc.clear if defined? ::Logging
    end

  end
end
