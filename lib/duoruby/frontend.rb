# frozen_string_literal: true

require "json"
require "duoruby/message"
require "duoruby/channel"
require "promise/v2" if RUBY_ENGINE == "opal"

module DuoRuby
  # Browser-side event hub. Manages the WebSocket connection and message dispatch.
  #
  # Frontend inherits the full {Channel} event system. Declare handlers at the
  # class level (inherited by subclasses) or add them at runtime on an instance.
  #
  # Unlike {Backend} handlers, Frontend event handlers receive *only* the message
  # params as keyword arguments — there is no client positional argument because
  # there is exactly one connection per frontend instance.
  #
  # A transport callable (proc or block) is responsible for delivering outbound
  # messages. Under Opal it is set automatically by {#connect}; in tests you can
  # supply any callable at construction time.
  #
  # @example Inline transport for testing
  #   delivered = []
  #   frontend = DuoRuby::Frontend.new { |msg| delivered << msg }
  #   frontend.send(:join, room: "lobby")
  #
  # @example Subclass with class-level handlers
  #   class MyFrontend < DuoRuby::Frontend
  #     on(:snapshot) { |rooms:, **| puts "rooms: #{rooms.join(', ')}" }
  #   end
  class Frontend < Channel
    require "duoruby/frontend/test_promise"
    require "duoruby/frontend/socket_transport"

    include SocketTransport

    # @return [Array<Hash>] every message sent through this frontend, for inspection
    attr_reader :sent

    # @return [Browser::Socket, nil] the active WebSocket, or nil before {#connect}
    attr_reader :socket

    # @param transport [Proc, nil] callable that delivers outbound messages;
    #   mutually exclusive with the block form. May be omitted and set later
    #   by {#connect}.
    # @yieldparam message [Hash] the serialized message to deliver
    def initialize(transport: nil, &transport_block)
      super()
      @transport = transport || transport_block
      @sent = []
      @pending_calls = {}
      @next_call_id = 0
    end

    # Sends +event+ with +params+ to the server.
    #
    # The message is appended to {#sent} and, if a transport is configured,
    # forwarded immediately.
    #
    # @param event [String, Symbol] the event name
    # @param params keyword arguments that become the message params
    # @return [Hash] the serialized message that was sent
    def send(event, **params)
      message = Message.new(event, **params).to_h
      sent << message
      @transport.call(message) if @transport
      message
    end

    def transport=(transport)
      @transport = transport
    end

    def call(event, **params)
      id = next_call_id
      promise = self.class.promise_class.new
      @pending_calls[id] = promise
      deliver(Message.request(event, id, **params).to_h)
      promise
    end

    # Opens the WebSocket connection and wires socket lifecycle events.
    #
    # Only available under Opal (requires +Browser::Socket+). Raises immediately
    # on CRuby. Raises if already connected.
    #
    # Sets up a JSON-serialising transport and forwards:
    # - socket +:open+  → triggers +:$connect+
    # - socket +:message+ → calls {#receive} with the parsed JSON payload
    # - socket +:close+ → triggers +:$disconnect+
    #
    # @param url [String, nil] the full WebSocket URL; defaults to the value
    #   returned by {.default_socket_url}
    # @param path [String] the socket path used when +url+ is not given
    # @return [self]
    # @raise [RuntimeError] if called outside Opal, or if already connected
    # Coerces +message+ and dispatches it to the appropriate event handlers.
    # Params are forwarded as keyword arguments only (no positional client arg).
    #
    # @param message [Message, Hash] the inbound message (raw parsed JSON or a Message)
    def receive(message)
      message = Message.coerce(message)
      return resolve_call(message) if message.event == Message::REPLY_EVENT
      return reject_call(message) if message.event == Message::ERROR_EVENT && message.reply_to

      dispatch(message.event, **message.params)
    end

    def deliver(message)
      sent << message
      @transport.call(message) if @transport
      message
    end

    def self.promise_class
      defined?(::PromiseV2) ? ::PromiseV2 : TestPromise
    end

    private

    def next_call_id
      @next_call_id += 1
      "call-#{@next_call_id}"
    end

    def resolve_call(message)
      promise = @pending_calls.delete(message.reply_to)
      promise&.resolve(message.params[:result])
    end

    def reject_call(message)
      promise = @pending_calls.delete(message.reply_to)
      promise&.reject(message.params)
    end
  end
end
