require 'rails_test_helper'

Dynflow::Bus.impl = Dynflow::Bus::RailsBus.new

describe 'transactions' do

  before do
    # we test transaction features so we can't really wrap the tests
    # inside the transaction, using truncation instead
    DatabaseCleaner.clean_with :truncation
    @event = Event.create!(:name => "test")
    @user = User.create!(:login => "root")
  end

  it 'runs planning phase in a transaction' do
    Actions::SendInvitations.trigger(@event, "Hello", ['root'])
    # success means a guest record was created
    Guest.all.size.must_equal 1

    proc do
      Actions::SendInvitations.trigger(@event, "Hello", ['root', 'failme'])
    end.must_raise Actions::Exceptions::PlanException
    # fails means the guest records were not affected at all
    Guest.all.size.must_equal 1
  end

  it 'runs the finalize phase in a transaction' do
    Actions::SendInvitations.trigger(@event, 'do not fail in finalization phase', ['root'])
    Guest.last.invitation_status.must_equal 'sent'

    proc do
      Actions::SendInvitations.trigger(@event, 'fail in finalization phase', ['root'])
    end.must_raise Actions::Exceptions::FinalizeException
    Guest.last.invitation_status.must_equal 'send_pending'
  end
end

describe 'execution plan persistence' do
  include TransactionalTests

  before do
    @event = Event.create!(:name => "test")
    @user = User.create!(:login => "root")
  end

  it 'returns the execution plan obejct when triggering an action' do
    ret = Actions::SendInvitations.trigger(@event, 'Hello', ['root'])
    ret.must_be_instance_of Dynflow::ExecutionPlan
  end

  it 'persists the execution plan' do
    plan = Actions::SendInvitations.trigger(@event, 'Hello', ['root'])
    plan.persistence.new_record?.must_equal false
  end

  it 'is able to restore the execution plan' do
    plan = Actions::SendInvitations.trigger(@event, 'fail in execution phase', ['root'])

    # TODO: status should be directly an execution plan property
    plan.persistence.status.must_equal 'paused'

    action = plan.actions.first
    action.input['invitation_message'] = 'success'
    Dynflow::Bus.impl.update_journal(plan.persistence, action)
    plan.persistence.reload
    Dynflow::Bus.impl.resume(plan.persistence)

    plan.persistence.status.must_equal 'finished'
  end
end
