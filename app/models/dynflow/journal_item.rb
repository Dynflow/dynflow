module Dynflow
  class JournalItem < ActiveRecord::Base

    belongs_to :journal
    attr_accessible :action, :status

    def action
      encoded_action = JSON.parse(self[:action]) rescue nil
      if encoded_action
        decoded_action = Dynflow::Message.decode(encoded_action)
        decoded_action.journal_item_id = self.id
        decoded_action.status = self.status
        return decoded_action
      end
    end

    def action=(action)
      self[:action] = action.encode.to_json
      self.status = action.status
    end
  end
end
