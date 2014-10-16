module Dynflow
  module TransactionAdapters
    class ActiveRecord < Abstract
      def transaction(&block)
        ::ActiveRecord::Base.transaction(&block)
      end

      def rollback
        raise ::ActiveRecord::Rollback
      end

      def cleanup
        ::ActiveRecord::Base.clear_active_connections!
      end
    end
  end
end
