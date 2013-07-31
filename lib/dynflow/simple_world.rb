module Dynflow
  class SimpleWorld < World
    def default_options
      super.merge(executor:            Executors::Parallel.new(self),
                  persistence_adapter: PersistenceAdapters::Memory.new,
                  transaction_adapter: TransactionAdapters::None.new)
    end
  end
end
