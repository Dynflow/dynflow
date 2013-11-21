module Dynflow
  class SimpleWorld < World
    def default_options
      super.merge(pool_size:           5,
                  persistence_adapter: PersistenceAdapters::Sequel.new('sqlite:/'),
                  transaction_adapter: TransactionAdapters::None.new)
    end
  end
end
