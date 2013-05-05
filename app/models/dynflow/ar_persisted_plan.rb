module Dynflow
  class ArPersistedPlan < ActiveRecord::Base

    has_many :ar_persisted_steps, :order => 'id'
    attr_accessible :status

    def steps
      self.ar_persisted_steps.map(&:step)
    end

    def run_steps
      self.steps.find_all { |step| step.is_a? Step::Run }
    end

    def finalize_steps
      self.steps.find_all { |step| step.is_a? Step::Finalize }
    end

    def execution_plan
      execution_plan = ExecutionPlan.new(self.run_steps, self.finalize_steps)
      execution_plan.status = self.status
      execution_plan.persistence = self
      return execution_plan
    end

    # vvvv interface required by Dynflow::Bus

    def persistence_id
      self.id
    end

    def self.persist(originator_class, execution_plan)
      persisted_plan = self.create! do |persisted_plan|
        persisted_plan.originator = originator_class.name
        persisted_plan.status = execution_plan.status
      end
      execution_plan.steps.each do |step|
        persisted_step = persisted_plan.ar_persisted_steps.create do |persisted_step|
          persisted_step.persist(step)
        end
        step.persistence = persisted_step
      end
      execution_plan.persistence = persisted_plan
      return persisted_plan
    end

    # update the persistence status base on the current status of execution_plan
    def persist(execution_plan)
      self.update_attributes!(status: execution_plan.status)
    end

  end
end
