module Dynflow
  class JournalItem < ActiveRecord::Base

    belongs_to :journal
    attr_accessible :action, :status

    def action
      encoded_action = JSON.parse(self[:action]) rescue nil
      if encoded_action
        decoded_action = Dynflow::Message.decode(encoded_action)
        decoded_action.persistence = self
        decoded_action.status = self.status
        return decoded_action
      end
    end

    def action=(action)
      self[:action] = action.encode.to_json
      self.status = action.status
    end

    # vvvv interface required by Dynflow::Action

    def persist(action)
      self.update_attributes!(:action => action)
    end

    # we don't persist the status right before run
    def before_run(action)
      # we don't update the s
    end

    def after_run(action)
      persist(action)
    end
  end
end
