module Dynflow
  module PersistenceAdapters

    # TODO use sequel for all of them
    require 'dynflow/persistence_adapters/abstract'
    require 'dynflow/persistence_adapters/memory'
    require 'dynflow/persistence_adapters/simple_file_storage'
    require 'dynflow/persistence_adapters/sequel'

  end
end
