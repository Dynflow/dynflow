module Dynflow
  class Worker

    def run(step)
      puts "Preparing step \n"
      step.prepare
      puts "Running step \n"
      step.run
      puts "Setting step status \n"
      step.status = 'success'
    rescue Exception => e
      puts "Step error: "

      step.error = {
        "exception" => e.class.name,
        "message"   => e.message,
        "backtrace"   => e.backtrace
      }
      step.status = 'error'

      puts step.error['exception']
      puts step.error['backtrace']
    ensure
      puts "Persisting step after run \n"
      step.persist_after_run
      return step
    end

  end
end
