module Dynflow
  module Persistence
    module ActiveRecord
      class PersistedStep < ::ActiveRecord::Base

        self.table_name = 'dynflow_ar_persisted_steps'

        belongs_to :persisted_plan
        attr_accessible :data, :status

        def step
          encoded_step = JSON.parse(self[:data]) rescue nil
          if encoded_step
            decoded_step = Dynflow::Step.decode(encoded_step)
            decoded_step.persistence = self
            decoded_step.status = self.status
            return decoded_step
          end
        end

        # vvvv interface required by Dynflow::Action

        def persistence_id
          self.id
        end

        def plan_persistence_id
          self.persisted_plan.id
        end

        def persist(step)
          self.update_attributes!(:data => step.encode.to_json, :status => step.status)
        end

        # we don't persist the status right before run
        def before_run(step)
          # we don't update the s
        end

        def after_run(step)
          persist(step)
        end
      end
    end
  end
end
