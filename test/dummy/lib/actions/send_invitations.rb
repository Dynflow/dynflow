module Actions
  class SendInvitations < Dynflow::Action

    def plan(event, invitation_message, invitees)
      invitees.each do |invitee|
        plan_action Invite, event, invitation_message, invitee
      end
    end

  end
end
