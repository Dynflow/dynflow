module Actions
  class Invite < Dynflow::Action

    input_format do
      param :event_id, Integer
      param :invitation_message, String
      param :guest_id, Integer
      param :email, string
    end

    def plan(event, invitation_message, invitee_login)
      if invitee_login == 'failme'
        raise Exceptions::PlanException
      end
      invitee = User.find_by_login!(invitee_login)
      guest = Guest.create!(:event_id => event.id,
                            :user_id => invitee.id,
                            :invitation_status => 'send_pending')
      email = "#{invitee_login}@example.com"

      plan_self('event_id' => event.id,
                'invitation_message' => invitation_message,
                'guest_id' => guest.id,
                'email'    => email)
    end

    def run
      if input['invitation_message'] == 'fail in execution phase'
        raise Exceptions::RunException
      end
      Rails.logger.debug "Sending message #{input['invitation_message']} to #{input['email']}"
      output['sent_at'] = Time.now.to_s
    end

    def finalize(outputs)
      Guest.find(input['guest_id']).update_attributes!(:invitation_status => 'sent')
      if input['invitation_message'] == 'fail in finalization phase'
        raise Exceptions::FinalizeException
      end
    end

  end
end
