module Dynflow
  module Serializers
    class Noop < Abstract

      def serialize(*args)
        args
      end

      def deserialize(serialized_args)
        serialized_args
      end

    end
  end
end
