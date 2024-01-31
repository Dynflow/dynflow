# frozen_string_literal: true

module Dynflow
  module Executors
    require 'dynflow/executors/parallel'

    class << self
      # Every time we run a code that can be defined outside of Dynflow,
      # we should wrap it with this method, and we can ensure here to do
      # necessary cleanup, such as cleaning ActiveRecord connections
      def run_user_code
        # Here we cover a case where the connection was already checked out from
        # the pool and had opened transactions. In that case, we should leave the
        # cleanup to the other runtime unit which opened the transaction. If the
        # connection was checked out or there are no opened transactions, we can
        # safely perform the cleanup.
        no_previously_opened_transactions = active_record_open_transactions.zero?
        yield
      ensure
        ::ActiveRecord::Base.clear_active_connections! if no_previously_opened_transactions && active_record_connected?
        ::Logging.mdc.clear if defined? ::Logging
      end

      private

      def active_record_open_transactions
        active_record_active_connection&.open_transactions || 0
      end

      def active_record_active_connection
        return unless defined?(::ActiveRecord) && ::ActiveRecord::Base.connected?
        # #active_connection? returns the connection if already established or nil
        ::ActiveRecord::Base.connection_pool.active_connection?
      end

      def active_record_connected?
        !!active_record_active_connection
      end
    end
  end
end
