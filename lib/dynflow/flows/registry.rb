# frozen_string_literal: true

module Dynflow
  module Flows
    class Registry
      class IdentifierTaken < ArgumentError; end
      class UnknownIdentifier < ArgumentError; end

      class << self
        def register!(klass, identifier)
          if (found = serialization_map[identifier])
            raise IdentifierTaken, "Error setting up mapping #{identifier} to #{klass}, it already maps to #{found}"
          else
            serialization_map.update(identifier => klass)
          end
        end

        def encode(klass)
          klass = klass.class unless klass.is_a?(Class)
          serialization_map.invert[klass] || raise(UnknownIdentifier, "Could not find mapping for #{klass}")
        end

        def decode(identifier)
          serialization_map[identifier] || raise(UnknownIdentifier, "Could not find mapping for #{identifier}")
        end

        def serialization_map
          @serialization_map ||= {}
        end
      end
    end
  end
end
