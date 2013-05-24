module Actions
  class LogInvitation < Dynflow::Action

    input_format do
      param :inv_input, Invite.input
    end

    def self.subscribe
      Invite
    end

    def finalize(outputs)
      Log.create!(:text => "'#{input['inv_input']['invitation_message']}' sent to #{input['inv_input']['email']}")
    end

  end
end
