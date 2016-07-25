require 'logger'

module Support
  module DummyExample
    class Dummy < Dynflow::Action
      def run; end
    end

    class MySerializer < Dynflow::Serializers::Noop
      def serialize(arg)
        raise 'Enforced serializer failure' if arg == :fail
        super arg
      end
    end

    class DummyCustomDelaySerializer < Dynflow::Action
      def delay(delay_options, *args)
        MySerializer.new(args)
      end
      def run; end
    end

    class FailingDummy < Dynflow::Action
      def run; raise 'error'; end
    end

    class Slow < Dynflow::Action
      def plan(seconds)
        sequence do
          plan_self interval: seconds
          plan_action Dummy
        end
      end

      def run
        sleep input[:interval]
        action_logger.debug 'done with sleeping'
        $slow_actions_done ||= 0
        $slow_actions_done +=1
      end
    end

    class Polling < Dynflow::Action
      include Dynflow::Action::Polling

      def invoke_external_task
        error! 'Trolling detected' if input[:text] == 'troll setup'
        { progress: 0, done: false }
      end

      def poll_external_task
        if input[:text] == 'troll progress' && !output[:trolled]
          output[:trolled] = true
          error! 'Trolling detected'
        end

        if input[:text] =~ /pause in progress (\d+)/
          TestPause.pause if external_task[:progress] == $1.to_i
        end

        progress = external_task[:progress] + 10
        { progress: progress, done: progress >= 100 }
      end

      def done?
        external_task && external_task[:progress] >= 100
      end

      def poll_interval
        0.001
      end

      def run_progress
        external_task && external_task[:progress].to_f / 100
      end
    end

    class WeightedPolling < Dynflow::Action

      def plan(input)
        sequence do
          plan_self(input)
          plan_action(Polling, input)
        end
      end

      def run
      end

      def finalize
        $dummy_heavy_progress = 'dummy_heavy_progress'
      end

      def run_progress_weight
        4
      end

      def finalize_progress_weight
        5
      end

      def humanized_output
        "You should #{output['message']}"
      end
    end

    class EventedAction < Dynflow::Action
      def run(event = nil)
        case event
        when "timeout"
          output[:event] = 'timeout'
          raise "action timeouted"
        when nil
          suspend do |suspended_action|
            if input[:timeout]
              world.clock.ping suspended_action, input[:timeout], "timeout"
            end
          end
        else
          self.output[:event] = event
        end
      end
    end

    class ComposedAction < Dynflow::Action
      def run(event = nil)
        match event,
              (on nil do
                 sub_plan = world.trigger(Dummy)
                 output[:sub_plan_id] = sub_plan.id
                 suspend do |suspended_action|
                   if input[:timeout]
                     world.clock.ping suspended_action, input[:timeout], "timeout"
                   end

                   sub_plan.finished.on_success! { suspended_action << 'finish' }
                 end
               end),
              (on 'finish' do
                 output[:event] = 'finish'
               end),
              (on 'timeout' do
                 output[:event] = 'timeout'
               end)
      end
    end
  end
end
