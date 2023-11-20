# frozen_string_literal: true

module Dynflow
  module Serializers
    # @abstract
    # Used to serialize and deserialize arguments for storage in a database.
    # Used by {DelayedPlan} to store arguments which should be passed into
    # the {Dynflow::Action}'s #plan method when the plan is executed.
    class Abstract
      attr_reader :args, :serialized_args, :serialized_kwargs

      # @param args [Array] arguments to be serialized
      # @param serialized_args [nil, Array] arguments in their serialized form
      def initialize(args, serialized_args = nil, kwargs = {}, serialized_kwargs = nil)
        @args = args
        @kwargs = kwargs
        @serialized_args = serialized_args
        @serialized_kwargs = serialized_kwargs
      end

      # Retrieves the arguments
      #
      # @raise [RuntimeError] if the deserialized arguments are not available
      # @return [Array] the arguments
      def args!
        raise "@args not set" if @args.nil?
        return @args
      end

      # Retrieves the arguments in the serialized form
      #
      # @raise [RuntimeError] if the serialized arguments are not available
      # @return [Array] the serialized arguments
      def serialized_args!
        raise "@serialized_args not set" if @serialized_args.nil?
        return @serialized_args
      end

      # Retrieves the arguments
      #
      # @raise [RuntimeError] if the deserialized arguments are not available
      # @return [Array] the arguments
      def kwargs!
        raise "@kwargs not set" if @kwargs.nil?
        return @kwargs
      end

      # Retrieves the arguments in the serialized form
      #
      # @raise [RuntimeError] if the serialized arguments are not available
      # @return [Array] the serialized arguments
      def serialized_kwargs!
        raise "@serialized_kwargs not set" if @serialized_kwargs.nil?
        return @serialized_kwargs
      end

      # Converts arguments into their serialized form, iterates over deserialized
      # arguments, applying {#serialize} to each of them
      #
      # @raise [RuntimeError] if the deserialized arguments are not available
      # @return [Array] the serialized arguments
      def perform_serialization!
        @serialized_args = args!.map { |arg| serialize arg }
        @serialized_kwargs = kwargs!.map { |k, v| serialize_kw(k, v) }
      end

      # Converts arguments into their deserialized form, iterates over serialized
      # arguments, applying {#deserialize} to each of them
      #
      # @raise [RuntimeError] if the serialized arguments are not available
      # @return [Array] the deserialized arguments
      def perform_deserialization!
        @args = serialized_args!.map { |arg| deserialize arg }
        @kwargs = serialized_kwargs!.reduce({}) { |acc, serialized| acc.merge(deserialize_kw(serialized)) }
      end

      # Converts an argument into it serialized form
      #
      # @param arg the argument to be serialized
      def serialize(arg)
        raise NotImplementedError
      end

      # Converts a serialized argument into its deserialized form
      #
      # @param arg the argument to be deserialized
      def deserialize(arg)
        raise NotImplementedError
      end

      def serialize_kw(key, value)
        [serialize(key), serialize(value)]
      end

      def deserialize_kw(serialized)
        k, v = serialized
        { k.to_sym => deserialize(v) }
      end
    end
  end
end
