class Guest < ActiveRecord::Base
  belongs_to :event
  belongs_to :user
  attr_accessible :event_id, :user_id, :invitation_status
end
