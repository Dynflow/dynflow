module Dynflow
  class Journal < ActiveRecord::Base

    has_many :journal_items, :order => 'id'
    attr_accessible :status

    def actions
      self.journal_items.map(&:action)
    end

    def execution_plan
      execution_plan = ExecutionPlan.new(self.actions)
      execution_plan.status = self.status
      execution_plan.persistence = self
      return execution_plan
    end

    # vvvv interface required by Dynflow::Bus

    def self.persist(originator_class, execution_plan)
      journal = self.create! do |journal|
        journal.originator = originator_class.name
        journal.status = execution_plan.status
      end
      execution_plan.actions.each do |action|
        journal_item = journal.journal_items.create do |journal_item|
          journal_item.action = action
        end
        action.persistence = journal_item
      end
      execution_plan.persistence = journal
      return journal
    end

    # update the persistence status base on the current status of execution_plan
    def persist(execution_plan)
      self.update_attributes!(status: execution_plan.status)
    end

  end
end
