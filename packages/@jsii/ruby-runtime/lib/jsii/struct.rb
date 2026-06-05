# frozen_string_literal: true

module Jsii
  # Base class for all JSII data types (structs) which pass data by-value.
  class Struct
    extend Jsii::FqnExtension

    # @return [String, nil] the by-reference handle for this struct, if any has been
    #   assigned (most structs are serialized purely by value and have no ref).
    attr_accessor :jsii_ref

    # Returns the struct's field values keyed by JSII (camelCase) wire names.
    # Always overridden by pacmak-generated subclasses; the base implementation
    # returns an empty hash so structs with no fields still serialize cleanly.
    #
    # @return [Hash{String=>Object}] field values keyed by JSII property name.
    def to_jsii
      # This should be overridden by the generated class
      {}
    end

    # Encodes this struct as a `$jsii.struct` wire envelope (fqn + data).
    #
    # @return [Hash{String=>Hash}] `{ "$jsii.struct" => { "fqn" => ..., "data" => ... } }`.
    def jsii_serialize
      {
        '$jsii.struct' => {
          'fqn' => self.class.jsii_fqn,
          'data' => Jsii::Serializer.dump(to_jsii)
        }
      }
    end

    # Two structs are equal when they share a class and produce identical
    # `to_jsii` payloads.
    #
    # @param other [Object] the value to compare against.
    # @return [Boolean] `true` iff `other` is the same class and has equal field values.
    def ==(other)
      return false unless other.class == self.class

      to_jsii == other.to_jsii
    end
    alias eql? ==

    # @return [Integer] a hash code derived from {#to_jsii}, consistent with {#==}.
    def hash
      to_jsii.hash
    end
  end
end
