module Dynflow
  class Worker

    def run(step)
      step.prepare
      step.run
      step.status = 'success'
    rescue Exception => e
      step.error = {
        "exception" => e.class.name,
        "message"   => e.message,
        "backtrace"   => e.backtrace
      }
      step.status = 'error'
    ensure
      step.persist_after_run
      return step.status
    end

  end
end
