# frozen_string_literal: true

require "duoruby/message"

module DuoRuby
  # Represents a single connected WebSocket client.
  #
  # Client wraps the low-level connection writer and acts as a typed
  # key-value store for per-connection application state (e.g. current
  # room, display name, authentication status).
  #
  # Instances are created by {Server#connect} and passed as the first
  # argument to every server event handler.
  #
  # @example Sending a message to a client
  #   client.send(:snapshot, rooms: ["lobby"], users: ["Alice"])
  #
  # @example Storing and reading application state
  #   client[:name] = "Alice"
  #   client[:name]  # => "Alice"
  class Client
    # @return [String] the unique connection identifier assigned by the server
    attr_reader :id

    # @return [Hash{Symbol => Object}] per-client application state
    attr_reader :attributes

    # @return [Hash{Symbol => Group}] groups this client currently belongs to
    attr_reader :groups

    attr_reader :metadata

    # @param id [String] a unique identifier for this connection
    # @param writer [Proc, nil] callable that accepts a serialized message Hash;
    #   mutually exclusive with the block form
    # @yieldparam message [Hash] the serialized message to deliver
    def initialize(id:, writer: nil, metadata: {}, &writer_block)
      @id = id
      @writer = writer || writer_block
      @metadata = metadata
      @attributes = {}
      @groups = {}
      @accepted = true
    end

    # Reads an application attribute by symbol key.
    # @param key [String, Symbol]
    # @return [Object, nil]
    def [](key)
      attributes[key.to_sym]
    end

    # Writes an application attribute. Keys are always stored as symbols.
    # @param key [String, Symbol]
    # @param value [Object]
    def []=(key, value)
      attributes[key.to_sym] = value
    end

    # Sends a message to this client over the WebSocket connection.
    #
    # @param event [String, Symbol] the event name
    # @param params keyword arguments that become the message params
    def send(event, **params)
      @writer.call(Message.new(event, **params).to_h)
    end

    def deliver(message)
      @writer.call(Message.coerce(message).to_h)
    end

    def join(group)
      group.add(self)
    end

    def leave(group)
      group.remove(self)
    end

    def accepted?
      @accepted
    end

    def reject(code: :unauthorized, message: "connection rejected", details: nil)
      @accepted = false
      deliver(Message.error(code: code, message: message, details: details))
      self
    end
  end
end
