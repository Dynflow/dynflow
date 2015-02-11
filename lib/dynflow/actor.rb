module Dynflow
  # Common parent for all the Dynflow actors defining some defaults
  # that we preffer here.
  class Actor < Concurrent::Actor::Context


    StartTermination = Algebrick.type do
      fields! terminated: Concurrent::IVar
    end

    # Behaviour that watches for polite asking for termination
    # and calls corresponding method on the context to do so
    class PoliteTermination < Concurrent::Actor::Behaviour::Abstract
      def on_envelope(envelope)
        if StartTermination === envelope.message
          context.start_termination(envelope.message.terminated)
          envelope.ivar.set true if !envelope.ivar.nil?
          Concurrent::Actor::Behaviour::MESSAGE_PROCESSED
        else
          pass envelope
        end
      end
    end

    include Algebrick::Matching

    def start_termination(ivar)
      @terminated = ivar
    end

    def finish_termination
      @terminated.set(true)
      reference.ask(:terminate!)
    end

    def terminating?
      !!@terminated
    end

    def behaviour_definition
      [*Concurrent::Actor::Behaviour.base,
       [Concurrent::Actor::Behaviour::Buffer, []],
       [Concurrent::Actor::Behaviour::SetResults, [:just_log]],
       [Concurrent::Actor::Behaviour::Awaits, []],
       [PoliteTermination, []],
       [Concurrent::Actor::Behaviour::ExecutesContext, []],
       [Concurrent::Actor::Behaviour::ErrorsOnUnknownMessage, []]]
    end
  end
end
