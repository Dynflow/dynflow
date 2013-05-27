module Dynflow
  module Test

    # provides helper methods for the unit testing.
    #
    # @example
    #  require 'dynflow/test/unit'
    #
    #  class ActionTest :: Test::Unit::TestCase
    #    include Dynflow::Test::Unit
    #
    #    def test_action_triggered
    #      action = dynflow_triggered_action do
    #        MyClass.say_hello('World')
    #      end
    #
    #      assert_instance_of HelloAction, action
    #      assert_equal {'name' => 'World'}, action.input
    #
    #      send_mail = action.sub_actions.first
    #      assert_equal SendMailAction, send_mail.action_class
    #      assert_equal 'world@example.com', send_mail.args.first
    #    end
    #  end
    module Unit

      # Capture the action triggered by the code in the block.
      #
      # @returns [Dynflow::Action] with Dynflow::Test::Unit::IsolatedAction
      def dynflow_triggered_action(&block)
        bus = Dynflow::Test::Unit::Bus.new
        Dynflow::Bus.using(bus, &block)
        return bus.trigerred_action
      end

      # Pseudo-bus capturing the triggered action and running the plan
      # of this action in isolation.
      class Bus

        attr_reader :trigerred_action

        def trigger(action_class, *args)
          @trigerred_action = action_class.new({}, :reference)
          @trigerred_action.singleton_class.send(:include, IsolatedAction)
          @trigerred_action.plan(*args)
        end

      end

      # runs the plan method in isolation, preventing the plan methods
      # of the sub actions to be executed, which is something we
      # expect for unit testing.
      # The planned sub actions and args are available in `IsolatedAction#sub_actions`
      module IsolatedAction

        # @returns [Array<ActionStub>] - stubs representing the
        #   actions that were planned by `plan_action` method.
        def sub_actions
          @sub_actions ||= []
        end

        def plan_action(action_class, *args)
          self.sub_actions << ActionStub.new(action_class, args)
        end

      end

      # Simulates the action being planned by `plan_action` method.
      class ActionStub

        attr_reader :action_class, :args

        # this interface might be used in the plan method of the
        # tested action when consuming one action's input/output in
        # other action's input.
        attr_reader :input, :output

        def initialize(action_class, args)
          @action_class = acting_class
          @args = args
          @input = Dynflow::Step::Reference.new(self, :input)
          @output = Dynflow::Step::Reference.new(self, :output)
        end

        def inspect
          "#{action_class.name}(#{args.map(&:inspect).join(', ')})"
        end

      end

    end
  end
end
