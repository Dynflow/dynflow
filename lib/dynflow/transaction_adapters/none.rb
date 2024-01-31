# frozen_string_literal: true

module Dynflow
  module TransactionAdapters
    class None < Abstract
      def transaction(&block)
        block.call
      end

      def rollback
      end
    end
  end
end
