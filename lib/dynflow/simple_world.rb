module Dynflow
  class SimpleWorld < World
    def default_options
      super.merge(executor_class:      Executors::Parallel,
                  pool_size:           5,
                  persistence_adapter: PersistenceAdapters::Memory.new,
                  transaction_adapter: TransactionAdapters::None.new)
    end
  end
end
