module Dynflow
  class Journal < ActiveRecord::Base

    has_many :journal_items
    attr_accessible :status
  end
end
