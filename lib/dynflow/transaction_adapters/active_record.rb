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

      def check(world)
        # missing reader in ConnectionPool
        ar_pool_size = ::ActiveRecord::Base.connection_pool.instance_variable_get(:@size)
        if (world.options[:pool_size] / 2.0) > ar_pool_size
          world.logger.warn 'Consider increasing ActiveRecord::Base.connection_pool size, ' +
                                "it's #{ar_pool_size} but there is #{world.options[:pool_size]} " +
                                'threads in Dynflow pool.'
        end
      end
    end
  end
end
