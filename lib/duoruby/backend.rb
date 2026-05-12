# frozen_string_literal: true

require "duoruby/message"
require "duoruby/channel"
require "duoruby/client"
require "duoruby/group"

module DuoRuby
  # Server-side event hub. Manages connected clients, groups, and message dispatch.
  #
  # Backend inherits the full {Channel} event system. Declare handlers at the
  # class level (inherited by subclasses) or add them at runtime on an instance.
  #
  # Event handler signatures differ from {Frontend}:
  # - Lifecycle events (+$connect+, +$disconnect+) receive the {Client} as the sole argument.
  # - Message events receive the {Client} as the first positional argument, followed
  #   by the message params as keyword arguments.
  #
  # @example Minimal backend
  #   backend = DuoRuby.backend do
  #     on(:$connect) { |client| puts "#{client.id} connected" }
  #     on(:chat)     { |client, text:| group(:lobby).send(:chat, text: text) }
  #   end
  #
  # @example Subclass with class-level handlers
  #   class MyBackend < DuoRuby::Backend
  #     on(:join) { |client, room:| group(room) << client }
  #     on(:say)  { |client, text:| group(client[:room]).send(:said, text: text) }
  #   end
  class Backend < Channel
    # @return [Hash{Symbol => Group}] all groups that have been accessed on this backend
    attr_reader :groups

    def initialize
      super
      @groups = {}
    end

    # Creates a new {Client} for the given connection and fires the +:$connect+ event.
    #
    # The +writer+ proc (or block) is called with a serialized message Hash whenever
    # {Client#send} is invoked. In practice the server passes a proc that writes
    # a JSON-encoded WebSocket text frame.
    #
    # @param id [String] a unique identifier for the connection
    # @param writer [Proc, nil] callable that delivers outbound messages; mutually
    #   exclusive with the block form
    # @yieldparam message [Hash] the serialized message to deliver
    # @return [Client]
    def connect(id:, writer: nil, metadata: {}, &writer_block)
      client = Client.new(id: id, writer: writer, metadata: metadata, &writer_block)
      return client.reject unless authenticate(client)

      dispatch(:$connect, client)
      client
    end

    def authenticate(_client)
      true
    end

    # Fires the +:$disconnect+ event and removes +client+ from all its groups.
    #
    # @param client [Client]
    # @return [Client]
    def disconnect(client)
      dispatch(:$disconnect, client)
      client.groups.values.each { |group| group.remove(client) }
      client
    end

    # Returns the {Group} with the given +name+, creating it on first access.
    #
    # @param name [String, Symbol]
    # @return [Group]
    def group(name)
      groups[name.to_sym] ||= Group.new(name)
    end

    # Sends +event+ with +params+ to all members of the named group.
    # Convenience wrapper around +group(group_name).send(event, **params)+.
    #
    # @param group_name [String, Symbol]
    # @param event [String, Symbol]
    # @param params keyword arguments forwarded to each client
    def broadcast(group_name, event, **params)
      group(group_name).send(event, **params)
    end

    # Coerces +message+ and dispatches it to the appropriate event handlers,
    # passing +client+ as the first positional argument.
    #
    # @param client [Client] the client that sent the message
    # @param message [Message, Hash] the inbound message (raw parsed JSON or a Message)
    def receive(client, message)
      message = Message.coerce(message)
      results = dispatch(message.event, client, **message.params)
      client.deliver(Message.reply(message.id, results.last)) if message.id
      results
    rescue StandardError => error
      raise unless message&.id

      client.deliver(Message.error(code: error.class.name, message: error.message, reply_to: message.id))
    end
  end
end
