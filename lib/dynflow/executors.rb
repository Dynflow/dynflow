module Dynflow
  module Executors
    # TODO taken form unreleased gem actress for now
    class Future
      class FutureHappen < StandardError
      end

      def initialize
        @queue           = Queue.new
        @value           = nil
        @ready           = false
        @write_semaphore = Mutex.new
        @read_semaphore  = Mutex.new
      end

      def ready?
        @ready
      end

      def set(result)
        @write_semaphore.synchronize do
          raise FutureHappen, 'future already happen, cannot set again' if ready?
          @queue << result
          @ready = true
          self
        end
      end

      def value
        @read_semaphore.synchronize { @value ||= @queue.pop }
      end

      def wait
        value
        self
      end
    end

    class Abstract
      def run(step)
        dispatch step
      end

      protected

      def dispatch(step)
        case step
        when ExecutionPlan::Sequence
          run_in_sequence(step.steps)
        when ExecutionPlan::Concurrence
          run_in_concurrence(step.steps)
        when Step then
          run_step(step)
        else
          raise ArgumentError, "Don't know how to run #{step}"
        end
      end

      def run_in_sequence(steps)
        raise NotImplementedError
      end

      def run_in_concurrence(steps)
        raise NotImplementedError
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
    end

    class PooledSequential < Abstract
      def initialize(pool_size = 20)
        @queue        = Queue.new
        @free_workers = Array.new(pool_size) { Thread.new { work } }
      end

      # @returns [Future] value of the future is set when computation is finished
      #     value can be result or an error
      def run(step)
        @queue.push [step, future = Future.new]
        return future
      end

      protected

      def run_in_sequence(steps)
        steps.each { |s| dispatch s }
      end

      def run_in_concurrence(steps)
        run_in_sequence(steps)
      end

      private

      def work
        loop do
          step, future = @queue.pop
          future.set begin
                       dispatch(step)
                     rescue => error
                       $stderr.puts "FATAL #{error.message} (#{error.class})\n#{error.backtrace.join("\n")}"
                       error
                     end
        end
      end
    end

  end
end
