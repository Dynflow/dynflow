# frozen_string_literal: true
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
    end
  end
end
