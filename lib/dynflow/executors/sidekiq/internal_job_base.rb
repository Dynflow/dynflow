module Dynflow
  module Executors
    module Sidekiq
      class InternalJobBase
        include ::Sidekiq::Worker
        extend ::Dynflow::Executors::Sidekiq::Serialization::WorkerExtension::ClassMethods
        sidekiq_options retry: false, backtrace: true

        def self.inherited(klass)
          klass.prepend(::Dynflow::Executors::Sidekiq::Serialization::WorkerExtension)
        end
      end
    end
  end
end
