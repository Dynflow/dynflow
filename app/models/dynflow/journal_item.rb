module Dynflow
  class JournalItem < ActiveRecord::Base

    belongs_to :journal
    attr_accessible :action

    def action
      encoded_action = JSON.parse(self[:action]) rescue nil
      if encoded_action
        action = Dynflow::Message.decode(encoded_action)
        action.journal_item_id = self.id
        return action
      end
    end

    def action=(action)
      self[:action] = action.encode.to_json
    end
  end
end
