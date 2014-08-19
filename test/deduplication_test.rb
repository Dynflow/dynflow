require_relative 'test_helper'

module Dynflow
  module DeduplicationTest  

    describe 'deduplication and run always' do

      include WorldInstance

      let :run_step do
        ::Dynflow::ExecutionPlan::Steps::RunStep
      end

      let :finalize_step do
        ::Dynflow::ExecutionPlan::Steps::FinalizeStep
      end

      let :plan_step do
        ::Dynflow::ExecutionPlan::Steps::PlanStep
      end

      let :step_count do
        ->(klass) do
          execution_plan.steps.values.select do |step|
            step.class == klass
          end.length
        end
      end

      let :executed_plan do
        world.execute(execution_plan.id).value
      end

      describe 'run always inheritance' do

        describe 'when no action is set to run always' do
          # 1       <- deduplicate!
          # +-2     <- inherits (deduplicate)
          # | +-3   <- inherits (deduplicate)
          # | | +-A <- inherits (deduplicate)
          # | +-3   <- inherits (deduplicate)
          # |   +-A <- inherits (deduplicate)
          # +-2     <- inherits (deduplicate)
          #   +-3   <- inherits (deduplicate)
          #   | +-A <- inherits (deduplicate)
          #   +-3   <- inherits (deduplicate)
          #     +-A <- inherits (deduplicate)

          let :execution_plan do
            world.plan(Support::DuplicateExample::Level1)
          end

          it 'deduplicates every level' do
            step_count.(plan_step).must_equal 11
            step_count.(run_step).must_equal 4
            step_count.(finalize_step).must_equal 3
          end

          it 'runs' do
            executed_plan.result.must_equal :success
          end
        end

        describe 'when level 3 is set to run always' do
          # 1       <- deduplicate!
          # +-2     <- inherits (deduplicate)
          # | +-3   <- run_always!
          # | | +-A <- inherits (run)
          # | +-3   <- run_always!
          # |   +-A <- inherits (run)
          # +-2     <- inherits (deduplicate)
          #   +-3   <- run_always!
          #   | +-A <- inherits (run)
          #   +-3   <- run_always!
          #     +-A <- inherits (run)

          let :execution_plan do
            world.plan(Support::DuplicateExample::Level1,
                       :run_always_l3 => true)
          end

          it 'deduplicates two top levels' do
            step_count.(plan_step).must_equal 11
            step_count.(run_step).must_equal 10
            step_count.(finalize_step).must_equal 6
          end
        end

        describe 'when level 2 is set to run always' do
          # 1       <- undefined (run)
          # +-2     <- run_always!
          # | +-3   <- inherits (run)
          # | | +-A <- inherits (run)
          # | +-3   <- inherits (run)
          # |   +-A <- inherits (run)
          # +-2     <- run_always!
          #   +-3   <- inherits (run)
          #   | +-A <- inherits (run)
          #   +-3   <- inherits (run)
          #     +-A <- inherits (run)

          let :execution_plan do
            world.plan(Support::DuplicateExample::Level1,
                       :run_always_l2 => true)
          end

          it 'deduplicates only level 1' do
            step_count.(plan_step).must_equal 11
            step_count.(run_step).must_equal 11
            step_count.(finalize_step).must_equal 7
          end
        end

        describe 'when level 1 is unset' do
          # 1       <- undefined (run)
          # +-2     <- inherits (run)
          # | +-3   <- inherits (run)
          # | | +-A <- inherits (run)
          # | +-3   <- inherits (run)
          # |   +-A <- inherits (run)
          # +-2     <- inherits (run)
          #   +-3   <- inherits (run)
          #   | +-A <- inherits (run)
          #   +-3   <- inherits (run)
          #     +-A <- inherits (run)

          let :execution_plan do
            world.plan(Support::DuplicateExample::Level1,
                       :run_always_l1 => true)
          end

          it 'does not deduplicate' do
            step_count.(plan_step).must_equal 11
            step_count.(run_step).must_equal 11
            step_count.(finalize_step).must_equal 7
          end

          it 'runs' do
            executed_plan.result.must_equal :success
          end
        end

        describe 'when top level is unset but lowest level is set not to run always' do
          # 1       <- undefined (run)
          # +-2     <- inherits (run)
          # | +-3   <- deduplicate!
          # | | +-A <- inherits from 3 (deduplicate)
          # | +-3   <- deduplicate!
          # |   +-A <- inherits from 3 (deduplicate)
          # +-2     <- inherits (run)
          #   +-3   <- deduplicate!
          #   | +-A <- inherits from 3 (deduplicate)
          #   +-3   <- deduplicate!
          #     +-A <- inherits from 3 (deduplicate)

          let :execution_plan do
            world.plan(Support::DuplicateExample::Level1,
                       :run_always_l1 => true,
                       :deduplicate_l3 => true)
          end

          it 'does deduplicate level 2, but not level 3' do
            step_count.(plan_step).must_equal 11
            step_count.(run_step).must_equal 5
            step_count.(finalize_step).must_equal 4
          end

          it 'runs' do
            executed_plan.result.must_equal :success
          end
        end

        describe 'when top level is unset but one of the level 3 actions is set not to run always' do
          # 1       <- undefined (run)
          # +-2     <- inherits(run)
          # | +-3   <- inherits (run)
          # | | +-A <- inherits (run)
          # | +-3   <- deduplicate!
          # |   +-A <- inherits from 3 (deduplicate)
          # +-2     <- inherits (run)
          #   +-3   <- inherits (run)
          #   | +-A <- inherits (run)
          #   +-3   <- inherits (run)
          #     +-A <- inherits (run)

          let :execution_plan do
            world.plan(Support::DuplicateExample::Level1,
                       :run_always_l1 => true,
                       :deduplicate_one_l3 => true)
          end

          it 'does deduplicate level 2, but not level 3' do
            step_count.(plan_step).must_equal 11
            step_count.(run_step).must_equal 9
            step_count.(finalize_step).must_equal 6
          end

          it 'runs' do
            executed_plan.result.must_equal :success
          end
        end
      end

      describe 'when no action is set to run always' do
        
        describe 'when no duplicates are planned' do
          let :execution_plan do
            world.plan(Support::DuplicateExample::TopLevelAction)
          end

          it 'plans each action' do
            step_count.(plan_step).must_equal 4
            step_count.(run_step).must_equal 3
            step_count.(finalize_step).must_equal 2
          end

        end

        describe 'when duplicates in run are planned' do
          let :execution_plan do
            world.plan(Support::DuplicateExample::TopLevelAction,
                       :duplicate_run => true)
          end

          it 'removes duplicates in run phase' do
            step_count.(plan_step).must_equal 4
            step_count.(run_step).must_equal 2
            step_count.(finalize_step).must_equal 0
          end

          it 'dereferences inputs' do
            inputs = executed_plan.actions.map { |action| action.input.values }.
              flatten
            refute inputs.any? { |i| i.is_a? ::Dynflow::ExecutionPlan::OutputReference }
          end
        end

        describe 'when duplicate in finalize are planned' do
          let :execution_plan do
            world.plan(Support::DuplicateExample::TopLevelAction,
                       :duplicate_finalize => true)
          end

          it 'removes duplicates in finalize phase' do
            step_count.(plan_step).must_equal 4
            step_count.(run_step).must_equal 0
            step_count.(finalize_step).must_equal 2
          end

        end

        describe 'when duplicates in run and finalize are planned' do
          let :execution_plan do
            world.plan(Support::DuplicateExample::TopLevelAction,
                       :duplicate_run => true,
                       :duplicate_finalize => true)
          end

          it 'removes duplicates from both run and finalize phase' do
            step_count.(plan_step).must_equal 4
            step_count.(run_step).must_equal 2
            step_count.(finalize_step).must_equal 2
          end

          it 'runs' do
            executed_plan = world.execute(execution_plan.id).value
            executed_plan.result.must_equal :success
          end

          it 'dereferences inputs' do
            inputs = executed_plan.actions.map { |action| action.input.values }.
                flatten
            refute inputs.any? { |i| i.is_a? ::Dynflow::ExecutionPlan::OutputReference }
          end
        end

      end

      describe 'when an action is set to run always' do

        describe 'when no duplicates are planned' do
          let :execution_plan do
            world.plan(Support::DuplicateExample::TopLevelAction,
                       :run_always => true)
          end

          it 'does not remove any duplicates' do
            step_count.(plan_step).must_equal 4
            step_count.(run_step).must_equal 3
            step_count.(finalize_step).must_equal 2
          end
        end

        describe 'when duplicates in run are planned' do
          let :execution_plan do
            world.plan(Support::DuplicateExample::TopLevelAction,
                       :duplicate_run => true,
                       :run_always => true)
          end

          it 'does not remove duplicates from run' do
            step_count.(plan_step).must_equal 4
            step_count.(run_step).must_equal 3
            step_count.(finalize_step).must_equal 0
          end

          it 'dereferences inputs' do
            inputs = executed_plan.actions.map { |action| action.input.values }.
                flatten
            refute inputs.any? { |i| i.is_a? ::Dynflow::ExecutionPlan::OutputReference }
          end
        end

        describe 'when duplicate in finalize are planned' do
          let :execution_plan do
            world.plan(Support::DuplicateExample::TopLevelAction,
                       :duplicate_finalize => true,
                       :run_always => true)
          end

          it 'does not remove duplicates from finalize' do
            step_count.(plan_step).must_equal 4
            step_count.(run_step).must_equal 0
            step_count.(finalize_step).must_equal 3
          end
        end

        describe 'when duplicates in run and finalize are planned' do
          let :execution_plan do
            world.plan(Support::DuplicateExample::TopLevelAction,
                       :duplicate_run => true,
                       :duplicate_finalize => true,
                       :run_always => true)
          end

          it 'does not remove duplicates from any phase' do
            step_count.(plan_step).must_equal 4
            step_count.(run_step).must_equal 3
            step_count.(finalize_step).must_equal 3
          end

          it 'runs' do
            executed_plan = world.execute(execution_plan.id).value
            executed_plan.result.must_equal :success
          end

          it 'dereferences inputs' do
            inputs = executed_plan.actions.map { |action| action.input.values }.
                flatten
            refute inputs.any? { |i| i.is_a? ::Dynflow::ExecutionPlan::OutputReference }
          end
        end

      end

    end

  end
end
