# frozen_string_literal: true
module Dynflow
  module Executors

    require 'dynflow/executors/parallel'

    # Every time we run a code that can be defined outside of Dynflow,
    # we should wrap it with this method, and we can ensure here to do
    # necessary cleanup, such as cleaning ActiveRecord connections
    def self.run_user_code
      yield
    ensure
      if defined?(::ActiveRecord) && ActiveRecord::Base.connected? && ActiveRecord::Base.connection.open_transactions.zero?
        ::ActiveRecord::Base.clear_active_connections!
      end
      ::Logging.mdc.clear if defined? ::Logging
    end

  end
end
