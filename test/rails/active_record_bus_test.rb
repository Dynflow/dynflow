require 'rails_test_helper'

Dynflow::Bus.impl = Dynflow::Bus::ActiveRecordBus.new

describe 'transactions' do

  before do
    # we test transaction features so we can't really wrap the tests
    # inside the transaction, using truncation instead
    DatabaseCleaner.clean_with :truncation
    @event = Event.create!(:name => "test")
    @user = User.create!(:login => "root")
  end

  it 'runs planning phase in a transaction' do
    plan = Actions::SendInvitations.trigger(@event, "Hello", ['root'])
    # success means a guest record was created
    Guest.all.size.must_equal 1

    Actions::SendInvitations.trigger(@event, "Hello", ['root', 'failme'])
    # fails means the guest records were not affected at all
    Guest.all.size.must_equal 1
  end

  it 'runs the finalize phase in a transaction' do
    Actions::SendInvitations.trigger(@event, 'do not fail in finalization phase', ['root'])
    Guest.last.invitation_status.must_equal 'sent'

    Actions::SendInvitations.trigger(@event, 'fail in finalization phase', ['root'])
    Guest.last.invitation_status.must_equal 'send_pending'
  end
end

describe 'execution plan persistence' do
  include TransactionalTests

  before do
    @event = Event.create!(:name => "test")
    @user = User.create!(:login => "root")
  end

  let(:bus) { Dynflow::Bus.impl }
  let(:original_plan) do
    plan = bus.prepare_execution_plan(Actions::SendInvitations, @event, 'Hello', ['root'])
    bus.persist_plan_if_possible(plan)
    plan
  end

  let(:restored_plan) do
    bus.persisted_plan(original_plan.persistence.persistence_id)
  end

  it 'creates a new object' do
    restored_plan.object_id.wont_equal original_plan.object_id
  end

  it 'preserves the status' do
    restored_plan.status.must_equal original_plan.status
  end

  it 'preserves the steps' do
    restored_plan.steps.must_equal original_plan.steps
  end

  it 'loads every persisted step just once (even when referenced)' do
    referenced_step = original_plan.finalize_steps[0].output.step
    step = original_plan.run_steps[0]
    step.equal?(referenced_step).must_equal true

    referenced_step = restored_plan.finalize_steps[0].output.step
    step = restored_plan.run_steps[0]
    step.equal?(referenced_step).must_equal true
  end

  it 'preserves the run_plan' do
    restored_run_plan = restored_plan.instance_variable_get('@run_plan')
    restored_run_plan.must_equal original_plan.run_plan
  end

end
