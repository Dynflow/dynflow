module Dynflow
  class Executor

    def run(run_plan)
      success =  case run_plan
                 when ExecutionPlan::Sequence then run_sequence(run_plan)
                 when ExecutionPlan::Concurrence then run_concurrence(run_plan)
                 when RunStep then run_step(run_plan)
                 else raise ArgumentError, "Don't konw how to run #{run_plan}"
                 end

      return success
    end

    def run_sequence(sequence)
      sequence.steps.each do |run_plan|
        run_sync(run_plan) or return false
      end
      return true
    end

    def run_concurrence(concurrence)
      success = true
      tasks = []

      concurrence.steps.each do |run_plan|
        task = run_async(run_plan)
        if task
          tasks << task
        else
          success = false
          break
        end
      end

      runs = wait_for(*tasks)
      unless runs.all?
        success = false
      end

      return success
    end

    def run_step(step)
      step.replace_references!
      return true if %w[skipped success].include?(step.status)
      step.persist_before_run
      success = step.catch_errors do
        step.output = {}
        step.action.run
      end
      step.persist_after_run
      return success
    end

    def run_sync(step)
      run(step)
    end

    # returns a task accepted by wait_for method
    def run_async(step)
      # default implementation doesn't do any concurrence.
      run(step)
    end

    # wait for tasks to finish, returns the result of calling run
    # for the step.
    def wait_for(*tasks)
      # default implementation returns the run results directly in the
      # run_async output
      return tasks
    end
  end
end
