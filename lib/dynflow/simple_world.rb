module Dynflow
  class SimpleWorld < World
    def initialize
      super Executors::PooledSequential.new(self),
            PersistenceAdapters::Memory.new,
            TransactionAdapters::None.new
    end
  end
end
