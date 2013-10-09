require_relative 'test_helper'

module Dynflow


  describe Action::Missing do
    include WorldInstance

    let :action_data do
      { class: 'RenamedAction',
        state: 'success',
        id: 123,
        input: {},
        execution_plan_id: 123 }
    end

    subject do
      Action.from_hash(action_data, :run_phase, :success, world)
    end

    specify { subject.action_class.name.must_equal 'RenamedAction' }
    specify { assert subject.is_a? Action }
  end


  describe 'children' do
    include WorldInstance

    smart_action_class   = Class.new(Dynflow::Action)
    smarter_action_class = Class.new(smart_action_class)

    it { refute smart_action_class.phase? }
    it { refute smarter_action_class.phase? }
    it { assert smarter_action_class.plan_phase.phase? }

    it { smart_action_class.all_children.must_include smarter_action_class }
    it { smart_action_class.all_children.size.must_equal 1 }
    it { smart_action_class.all_children.wont_include smarter_action_class.plan_phase }
    it { smart_action_class.all_children.wont_include smarter_action_class.run_phase }
    it { smart_action_class.all_children.wont_include smarter_action_class.finalize_phase }

    describe 'World#subscribed_actions' do
      event_action_class      = Class.new(Dynflow::Action)
      subscribed_action_class = Class.new(Dynflow::Action) do
        singleton_class.send(:define_method, :subscribe) { event_action_class }
      end

      it { subscribed_action_class.subscribe.must_equal event_action_class }
      it { world.subscribed_actions(event_action_class).must_include subscribed_action_class }
      it { world.subscribed_actions(event_action_class).size.must_equal 1 }
    end
  end
end
