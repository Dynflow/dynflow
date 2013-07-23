module Dynflow
  module TransactionAdapters
    class Abstract
      def transaction(&block)
        raise NotImplementedError
      end

      def rollback
        raise NotImplementedError
      end
    end
  end
end
