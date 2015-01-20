module Dynflow
  module Connectors
    class Abstract
      include Algebrick::TypeCheck

      def start_listening(world)
        raise NotImplementedError
      end

      def stop_listening(world)
        raise NotImplementedError
      end

      def terminate
        raise NotImplementedError
      end

      def send(receiver, object)
        raise NotImplementedError
      end
    end
  end
end
