module Dynflow
  class Journal < ActiveRecord::Base

    has_many :journal_items, :order => 'id'
    attr_accessible :status

    def actions
      self.journal_items.map(&:action)
    end
  end
end
