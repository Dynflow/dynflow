module Dynflow
  module Serializers
    class Abstract

      attr_reader :args, :serialized_args

      def initialize(args, serialized_args = nil)
        @args = args
        @serialized_args = serialized_args
      end

      def args
        raise "@args not set" if @args.nil?
        return @args
      end

      def serialized_args
        raise "@serialized_args not set" if @serialized_args.nil?
        return @serialized_args
      end

      def perform_serialization!
        @serialized_args = serialize
      end

      def perform_deserialization!
        raise "@serialized_args not set" if @serialized_args.nil?
        @args = deserialize
      end

      def serialize
        raise NotImplementedError
      end

      def deserialize
        raise NotImplementedError
      end

    end
  end
end
