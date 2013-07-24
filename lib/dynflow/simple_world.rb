module Dynflow
  class SimpleWorld < World
    def initialize
      super Executors::Sequential.new,
            PersistenceAdapters::Memory.new,
            TransactionAdapters::None.new
    end
  end
end
