module Dynflow
  class Journal < ActiveRecord::Base

    has_many :journal_items
    attr_accessible :status

    def actions
      self.journal_items.map(&:action)
    end
  end
end
