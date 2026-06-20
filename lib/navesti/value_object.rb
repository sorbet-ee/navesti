# frozen_string_literal: true

module Navesti
  # Base for Navesti's frozen value objects (docs/02-domain-model.md).
  #
  # Subclasses declare their fields with `attribute`. Construction takes
  # keyword arguments, validates required fields, freezes the instance, and
  # exposes readers. "Modification" is `with(...)`, which returns a new frozen
  # instance. Objects are compared by value.
  #
  # Cross-cutting rules honoured here:
  #   - immutable/frozen at construction
  #   - constructors fail loudly on missing required fields
  #   - `raw` evidence (when present) is carried, never parsed back out of
  class ValueObject
    class << self
      # Declares an attribute. Required by default; pass `required: false`
      # to allow nil. `default:` supplies a value when the key is absent.
      def attribute(name, required: true, default: :__none__)
        attributes[name] = { required: required, default: default }
        attr_reader(name)
      end

      def attributes
        @attributes ||= superclass.respond_to?(:attributes) ? superclass.attributes.dup : {}
      end
    end

    def initialize(**kwargs)
      unknown = kwargs.keys - self.class.attributes.keys
      unless unknown.empty?
        raise ValidationError, "#{self.class}: unknown attribute(s) #{unknown.join(', ')}"
      end

      self.class.attributes.each do |name, opts|
        value = if kwargs.key?(name)
                  kwargs[name]
                elsif opts[:default] != :__none__
                  opts[:default]
                end

        if value.nil? && opts[:required]
          raise ValidationError, "#{self.class}: missing required attribute :#{name}"
        end

        instance_variable_set("@#{name}", value)
      end

      validate
      freeze_attributes
    end

    # Returns a new instance with the given attributes replaced.
    def with(**changes)
      self.class.new(**to_h.merge(changes))
    end

    def to_h
      self.class.attributes.keys.each_with_object({}) do |name, acc|
        acc[name] = instance_variable_get("@#{name}")
      end
    end

    def ==(other)
      other.is_a?(self.class) && other.to_h == to_h
    end
    alias eql? ==

    def hash
      [self.class, to_h].hash
    end

    private

    # Subclasses override to add semantic validation (raise ValidationError).
    def validate; end

    # Freezes the instance and recursively freezes each attribute value, so
    # preserved `raw` evidence (nested provider JSON hashes/arrays) is truly
    # immutable after construction — audit integrity, not just a frozen top
    # level. Provider responses are small, so the recursion cost is negligible.
    def freeze_attributes
      self.class.attributes.each_key do |name|
        deep_freeze(instance_variable_get("@#{name}"))
      end
      freeze
    end

    def deep_freeze(value)
      case value
      when Hash
        value.each { |k, v| deep_freeze(k); deep_freeze(v) }
      when Array
        value.each { |v| deep_freeze(v) }
      end
      value.freeze
    end
  end
end
