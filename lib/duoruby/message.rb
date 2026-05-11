# frozen_string_literal: true

require "duoruby/version"

module DuoRuby
  # Represents a single WebSocket message: an event name and a keyword params hash.
  #
  # Messages are the protocol unit shared between backend and frontend. They
  # serialize to a plain Hash for JSON transport and can be coerced back from
  # that same Hash (with either string or symbol keys).
  #
  # @example Creating a message
  #   msg = Message.new("chat", text: "hello")
  #   msg.event   # => "chat"
  #   msg.params  # => {text: "hello"}
  #   msg.to_h    # => {"event" => "chat", "params" => {"text" => "hello"}}
  #
  # @example Coercing from a parsed JSON hash
  #   Message.coerce("event" => "chat", "params" => {"text" => "hello"})
  class Message
    attr_reader :event, :params

    # Coerces +value+ into a Message.
    #
    # If +value+ is already a Message it is returned unchanged.
    # Otherwise +value+ is treated as a Hash with string or symbol keys
    # containing an +event+ key and an optional +params+ key.
    #
    # @param value [Message, Hash] the value to coerce
    # @return [Message]
    def self.coerce(value)
      return value if value.is_a?(Message)

      params = value.fetch("params") { value.fetch(:params, {}) }
      new(value.fetch("event") { value.fetch(:event) }, **params.transform_keys(&:to_sym))
    end

    # @param event [String, Symbol] the event name; stored as a String
    # @param params [Hash] keyword params accompanying the event
    def initialize(event, **params)
      @event = event.to_s
      @params = params
    end

    # Serializes the message to a plain Hash suitable for JSON encoding.
    # Both the +event+ key and all +params+ keys are strings.
    #
    # @return [Hash]
    def to_h
      {"event" => event, "params" => params.transform_keys(&:to_s)}
    end
  end
end
