module Dynflow
  module Executors
    module Sidekiq
      # Module to prepend the Sidekiq job to handle the serialization
      module Serialization
        def self.serialize(value)
          Dynflow.serializer.dump(value)
        end

        def self.deserialize(value)
          value = Utils::IndifferentHash.new(value) if value.is_a? Hash
          Dynflow.serializer.load(value)
        end

        module WorkerExtension
          # Overriding the Sidekiq entry method to perform additional serialization preparation
          module ClassMethods
            def client_push(opts)
              opts['args'] = opts['args'].map { |a| Serialization.serialize(a) }
              super(opts)
            end
          end

          def perform(*args)
            args = args.map { |a| Serialization.deserialize(a) }
            super(*args)
          end
        end
      end
    end
  end
end
