module Dynflow
  module Serializers
    class Noop < Abstract

      def serialize
        args
      end

      def deserialize
        serialized_args
      end

    end
  end
end
