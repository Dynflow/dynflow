module Dynflow

  module MethodicActor
    def on_message(message)
      method, *args = message
      self.send(method, *args)
    end
  end

  # Common parent for all the Dynflow actors defining some defaults
  # that we preffer here.
  class Actor < Concurrent::Actor::Context

    include MethodicActor

    # Behaviour that watches for polite asking for termination
    # and calls corresponding method on the context to do so
    class PoliteTermination < Concurrent::Actor::Behaviour::Abstract
      def on_envelope(envelope)
        message, terminated_future = envelope
        if :start_termination == message
          context.start_termination(terminated_future)
          envelope.future.success true if !envelope.future.nil?
          Concurrent::Actor::Behaviour::MESSAGE_PROCESSED
        else
          pass envelope
        end
      end
    end

    include Algebrick::Matching

    def start_termination(future)
      @terminated = future
    end

    def finish_termination
      @terminated.success(true)
      reference.tell(:terminate!)
    end

    def terminating?
      !!@terminated
    end

    def behaviour_definition
      [*Concurrent::Actor::Behaviour.base(:just_log),
       Concurrent::Actor::Behaviour::Buffer,
       [Concurrent::Actor::Behaviour::SetResults, :just_log],
       Concurrent::Actor::Behaviour::Awaits,
       PoliteTermination,
       Concurrent::Actor::Behaviour::ExecutesContext,
       Concurrent::Actor::Behaviour::ErrorsOnUnknownMessage]
    end
  end
end
