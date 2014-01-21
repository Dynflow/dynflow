module Dynflow
  module TransactionAdapters
    class Abstract
      # start transaction around +block+
      def transaction(&block)
        raise NotImplementedError
      end

      # rollback the transaction
      def rollback
        raise NotImplementedError
      end

      # Called on each thread after work is done.
      # E.g. it's used to checkin ActiveRecord connections back to pool.
      def cleanup
        # override if needed
      end

      # Called after World instantiation, it can be used to check Dynflow configuration etc.
      def check(world)
        # override if needed
      end
    end
  end
end
