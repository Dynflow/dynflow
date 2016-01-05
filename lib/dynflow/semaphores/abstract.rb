module Dynflow
  module Semaphores
    class Abstract

      # Tries to get ticket from the semaphore
      # Returns true if thing got a ticket
      # Rturns false otherwise and puts the thing into the semaphore's queue
      def wait(thing)
        raise NotImplementedError
      end

      # Gets first object from the queue
      def get_waiting
        raise NotImplementedError
      end

      # Checks if there are objects in the queue
      def has_waiting?
        raise NotImpelementedError
      end

      # Returns n tickets to the semaphore
      def release(n = 1)
        raise NotImplementedError
      end

      # Saves the semaphore's state to some persistent storage
      def save
        raise NotImplementedError
      end

      # Tries to get n tickets
      # Returns n if the semaphore has free >= n
      # Returns free if n > free
      def get(n = 1)
        raise NotImplementedErrorn
      end

      # Requests all tickets
      # Returns all free tickets from the semaphore
      def drain
        raise NotImplementedError
      end
    end
  end
end
