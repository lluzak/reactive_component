# frozen_string_literal: true

module ReactiveComponent
  # Raised when an extracted template expression returns something that is
  # not a primitive — e.g. a full ActiveRecord record, a custom object, or
  # a Date/Time. Broadcast payloads are JSON-serialized and visible to every
  # connected client, so letting a record through would leak every column
  # (including `password_digest` and tokens). Rather than silently coerce,
  # we raise so the developer fixes the template.
  class UnsafeBroadcastValueError < StandardError; end

  def self.sanitize_for_broadcast(value, source: nil)
    return value if value.nil? || value.is_a?(TrueClass) || value.is_a?(FalseClass)
    return value if value.is_a?(Integer) || value.is_a?(Float) || value.is_a?(String)
    return value.to_s if value.is_a?(Symbol)
    return value.map { |v| sanitize_for_broadcast(v, source: source) } if value.is_a?(Array)

    if value.is_a?(Hash)
      return value.each_with_object({}) do |(k, v), h|
        key = k.is_a?(Symbol) ? k.to_s : k
        raise_unsafe!(k, source, context: 'Hash key') unless key.is_a?(String) || key.is_a?(Integer)
        h[key] = sanitize_for_broadcast(v, source: source)
      end
    end

    raise_unsafe!(value, source)
  end

  def self.raise_unsafe!(value, source, context: 'Extracted expression')
    label = source ? "`#{source}`" : 'an extracted expression'
    hint =
      if defined?(ActiveRecord::Base) && value.is_a?(ActiveRecord::Base)
        "Narrow the ERB to a specific column (e.g. `#{source || '@record'}.name`) — " \
          'shipping the record would leak every column over ActionCable.'
      elsif value.is_a?(Time) || value.is_a?(Date) || (defined?(ActiveSupport::TimeWithZone) && value.is_a?(ActiveSupport::TimeWithZone))
        "Call a formatter in the template (e.g. `#{source}.iso8601` or `time_ago_in_words(#{source})`)."
      else
        'Convert the value to a primitive in the template ' \
          '(String, Integer, Float, Boolean, nil, Symbol, or Array/Hash of those) before outputting it.'
      end

    raise UnsafeBroadcastValueError,
          "[ReactiveComponent] #{context} #{label} returned a #{value.class.name}, which is not safe to broadcast. #{hint}"
  end
  private_class_method :raise_unsafe!
end
