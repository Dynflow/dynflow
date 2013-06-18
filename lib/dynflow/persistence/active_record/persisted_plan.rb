module Dynflow
  module Persistence
    module ActiveRecord
      class PersistedPlan < ::ActiveRecord::Base

        self.table_name = 'dynflow_ar_persisted_plans'

        has_many :persisted_steps, :order => 'id'
        attr_accessible :status

        serialize :serialized_run_plan

        def steps
          self.persisted_steps.map(&:step)
        end

        # vvvv interface required by Dynflow::Bus

        def persistence_id
          self.id
        end

        def persisted_step_ids(step_type)
          persisted_steps = self.persisted_steps.find_all do |persisted|
            persisted.step.is_a? step_type
          end

          persisted_steps.map(&:persistence_id)
        end

        def plan_step_ids
          persisted_step_ids(Step::Plan)
        end

        def run_step_ids
          persisted_step_ids(Step::Run)
        end

        def finalize_step_ids
          persisted_step_ids(Step::Finalize)
        end

        def self.persisted_plans(status = nil)
          scope = self
          if status
            scope = scope.where(:status => status)
          end
          scope.order('updated_at DESC').all
        end

        def self.persisted_plan(persistence_id)
          self.find(persistence_id)
        end

        def self.persisted_step(persistence_id)
          PersistedStep.find(persistence_id).step
        end

        def self.persist(execution_plan)
          persisted_plan = self.create! do |persisted_plan|
            persisted_plan.status = execution_plan.status
          end
          execution_plan.steps.each do |step|
            persisted_step = persisted_plan.persisted_steps.create do |persisted_step|
              persisted_step.persist(step)
            end
            step.persistence = persisted_step
          end
          execution_plan.persistence = persisted_plan

          yield persisted_plan if block_given?

          persisted_plan.save!
          return persisted_plan
        end

        # update the persistence status base on the current status of execution_plan
        def persist(execution_plan)
          self.update_attributes!(status: execution_plan.status)
        end

      end
    end
  end
end
