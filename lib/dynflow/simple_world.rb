module Dynflow
  class SimpleWorld < World
    def initialize
      super Executors::Sequential.new, PersistenceAdapters::Memory.new, TransactionAdapters::Dummy.new
    end
  end
end
