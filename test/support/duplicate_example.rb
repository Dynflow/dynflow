module Support
  module DuplicateExample

    class Level1 < Dynflow::Action
      
      def plan(options = {})
        deduplicate!
        run_always_l1 = options.fetch(:run_always_l1, false)
        run_always! if run_always_l1
        plan_self
        plan_action(Level2, options.reject { |key, value| key == :deduplicate_one_l3 })
        plan_action(Level2, options)
      end

      def run
      end

      def finalize
      end

    end

    class Level2 < Dynflow::Action
      
      def plan(options = {})
        run_always_l2 = options.fetch(:run_always_l2, false)
        run_always! if run_always_l2
        plan_action(Level3, options.reject { |key, value| key == :deduplicate_one_l3 })
        plan_action(Level3, options)
        plan_self

      end

      def run
      end

      def finalize
      end

    end

    class Level3 < Dynflow::Action
      
      def plan(options = {})
        run_always_l3 = options.fetch(:run_always_l3, false)
        deduplicate_l3 = options.fetch(:deduplicate_l3, false)
        deduplicate_one_l3 = options.fetch(:deduplicate_one_l3, false)
        run_always! if run_always_l3
        deduplicate! if deduplicate_l3 || deduplicate_one_l3
        plan_action(ActionWithRun, "name", false)
        plan_self
      end

      def run
      end

      def finalize
      end

    end
    

    class TopLevelAction < Dynflow::Action

      def plan(options = {})
        deduplicate!
        dup_run = options.fetch(:duplicate_run, false)
        dup_fin = options.fetch(:duplicate_finalize, false)
        dup_all = dup_run && dup_fin
        run_always = options.fetch(:run_always, false)
        if dup_all
          action1 = plan_action(ActionWithRunAndFinalize, "name", run_always)
          action2 = plan_action(ActionWithRunAndFinalize, "name", run_always)
          plan_action(ActionWithRunAndFinalize, action2.output[:response], run_always)
        elsif dup_run
          action1 = plan_action(ActionWithRun, "name", run_always)
          action2 = plan_action(ActionWithRun, "name", run_always)
          plan_action(ActionWithRun, action2.output[:response], run_always)
        elsif dup_fin
          plan_action(ActionWithFinalize, "name", run_always)
          plan_action(ActionWithFinalize, "name", run_always)
          plan_action(ActionWithFinalize, "name2", run_always)
        else
          plan_action(ActionWithRun, "name", run_always)
          plan_action(ActionWithRunAndFinalize, "name", run_always)
          plan_action(ActionWithRunAndFinalize, "name2", run_always)
        end

      end

    end

    class ActionWithRun < Dynflow::Action

      def plan(name, run_always)
        run_always! if run_always
        plan_self(:name => name)
      end

      def run
        output[:response] = "name2"
      end

    end

    class ActionWithFinalize < Dynflow::Action

      def plan(name, run_always)
        run_always! if run_always
        plan_self(:name => name)
      end

      def finalize
      end

    end

    class ActionWithRunAndFinalize < Dynflow::Action

      def plan(name, run_always)
        run_always! if run_always
        plan_self(:name => name)
      end
      
      def run
        output[:response] = "name2"
      end

      def finalize
      end

    end
  
  end
end

        
