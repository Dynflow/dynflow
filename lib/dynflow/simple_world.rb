module Dynflow
  class SimpleWorld < World
    def initialize(options_hash = {}, &options_block)
      super options_hash, &options_block
      at_exit { self.terminate.wait } if options[:auto_terminate]
      # we can check consistency here because SimpleWorld doesn't expect
      # remote executor being in place.
      self.consistency_check
    end

    def default_options
      super.merge(pool_size:           5,
                  persistence_adapter: PersistenceAdapters::Sequel.new('sqlite:/'),
                  transaction_adapter: TransactionAdapters::None.new,
                  auto_terminate:      true)
    end
  end
end
