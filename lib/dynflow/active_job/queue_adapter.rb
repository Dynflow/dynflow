# frozen_string_literal: true

module Dynflow
  module ActiveJob
    module QueueAdapters
      module QueueMethods
        def enqueue(job)
          ::Rails.application.dynflow.world.trigger do |world|
            job.provider_job_id = job.job_id
            world.plan_with_options(id: job.provider_job_id, action_class: JobWrapper, args: [job.serialize])
          end
        end

        def enqueue_at(job, timestamp)
          job.provider_job_id = job.job_id
          ::Rails.application.dynflow.world
                 .delay_with_options(id: job.provider_job_id,
                                action_class: JobWrapper,
                                delay_options: { :start_at => Time.at(timestamp) },
                                args: [job.serialize])
        end
      end

      # To use Dynflow, set the queue_adapter config to +:dynflow+.
      #
      #   Rails.application.config.active_job.queue_adapter = :dynflow
      class DynflowAdapter
        # For ActiveJob >= 5
        include QueueMethods

        # For ActiveJob <= 4
        extend QueueMethods
      end

      class JobWrapper < Dynflow::Action
        def queue
          input[:queue].to_sym
        end

        def plan(attributes)
          input[:job_class] = attributes['job_class']
          input[:queue] = attributes['queue_name']
          input[:job_data] = attributes
          plan_self
        end

        def run
          ::ActiveJob::Base.execute(input[:job_data])
        end

        def label
          input[:job_class]
        end

        def rescue_strategy
          Action::Rescue::Skip
        end
      end
    end
  end
end
