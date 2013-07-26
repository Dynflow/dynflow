require_relative 'test_helper'

module Dynflow
  #class ActionTest < Action
  #
  #  output_format do
  #    param :id, String
  #  end
  #
  #  def run
  #    output['id'] = input['name']
  #  end
  #
  #end
  #
  #describe 'running an action' do
  #
  #  it 'executed the run method storing results to output attribute'do
  #    action = ActionTest.new('name' => 'zoo')
  #    action.run
  #    action.output.must_equal('id' => "zoo")
  #  end
  #
  #end


  describe 'children' do
    smart_action_class   = Class.new(Dynflow::Action)
    smarter_action_class = Class.new(smart_action_class)

    it { refute smart_action_class.phase? }
    it { refute smarter_action_class.phase? }
    it { assert smarter_action_class.plan_phase.phase? }

    it { smart_action_class.all_children.must_include smarter_action_class }
    it { smart_action_class.all_children.size.must_equal 1 }
    it { smart_action_class.all_children.wont_include smarter_action_class.plan_phase }
    it { smart_action_class.all_children.wont_include smarter_action_class.run_phase }
    it { smart_action_class.all_children.wont_include smarter_action_class.final_phase }

    describe 'World#subscribed_actions' do
      event_action_class      = Class.new(Dynflow::Action)
      subscribed_action_class = Class.new(Dynflow::Action) do
        singleton_class.send(:define_method, :subscribe) { event_action_class }
      end

      world = SimpleWorld.new

      it { subscribed_action_class.subscribe.must_equal event_action_class }
      it { world.subscribed_actions(event_action_class).must_include subscribed_action_class }
      it { world.subscribed_actions(event_action_class).size.must_equal 1 }
    end
  end
end
