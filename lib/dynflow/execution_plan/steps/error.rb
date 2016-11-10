module Dynflow
  module ExecutionPlan::Steps
    class Error < Serializable
      extend Algebrick::Matching
      include Algebrick::TypeCheck

      attr_reader :exception_class, :message, :backtrace

      def self.new(*args)
        case args.size
        when 1
          match obj = args.first,
                (on String do
                  super(StandardError, obj, caller, nil)
                end),
                (on Exception do
                  super(obj.class, obj.message, obj.backtrace, obj)
                end)
        when 3, 4
          super(*args.values_at(0..3))
        else
          raise ArgumentError, "wrong number of arguments #{args}"
        end
      end

      def initialize(exception_class, message, backtrace, exception)
        @exception_class = Child! exception_class, Exception
        @message         = Type! message, String
        @backtrace       = Type! backtrace, Array
        @exception       = Type! exception, Exception, NilClass
      end

      def self.new_from_hash(hash)
        exception_class = begin
                            Utils.constantize(hash[:exception_class])
                          rescue NameError
                            Errors::UnknownError.for_exception_class(hash[:exception_class])
                          end
        self.new(exception_class, hash[:message], hash[:backtrace], nil)
      end

      def to_hash
        recursive_to_hash class:           self.class.name,
                          exception_class: exception_class.to_s,
                          message:         message,
                          backtrace:       backtrace
      end

      def to_s
        format '%s (%s)\n%s',
               (@exception || self).message,
               (@exception ? @exception.class : exception_class),
               (@exception || self).backtrace
      end

      def exception
        @exception ||
          exception_class.exception(message).tap { |e| e.set_backtrace backtrace }
      end
    end
  end
end
