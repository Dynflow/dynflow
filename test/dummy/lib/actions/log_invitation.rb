module Actions
  class LogInvitation < Dynflow::Action

    input_format do
      param :event_id, Integer
      param :invitation_message, String
      param :guest_id, Integer
      param :email, string
    end

    def self.subscribe
      Invite
    end

    def finalize(outputs)
      Log.create!(:text => "'#{input['invitation_message']}' sent to #{input['email']}")
    end

  end
end
