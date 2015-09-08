module Dynflow
  module Serializers
    class Noop < Abstract

      def serialize(arg)
        arg
      end

      def deserialize(arg)
        arg
      end

    end
  end
end
