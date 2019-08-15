# frozen_string_literal: true
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

        def worker_id
          ::Sidekiq::Logging.tid
        end

        def telemetry_options(work_item)
          { queue: work_item.queue.to_s, world: Dynflow.process_world.id, worker: worker_id }
        end
      end
    end
  end
end
