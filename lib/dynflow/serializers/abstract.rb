module Dynflow
  module Serializers
    class Abstract

      def serialize(*args)
        raise NotImplementedError
      end

      def deserialize(serialized_args)
        raise NotImplementedError
      end

    end
  end
end
