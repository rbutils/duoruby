# frozen_string_literal: true

require "json"
require "duoruby/message"
require "duoruby/channel"

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
    def connect(url: nil, path: "/duoruby/socket")
      raise "already connected" if @socket

      @socket = self.class.socket_class.new(url || self.class.default_socket_url(path))
      @transport = proc { |message| socket.write(JSON.generate(message)) }

      socket.on(:open) { trigger(:$connect) }
      socket.on(:message) { |event| receive(JSON.parse(event.data)) }
      socket.on(:close) { trigger(:$disconnect) }
      self
    end

    # Coerces +message+ and dispatches it to the appropriate event handlers.
    # Params are forwarded as keyword arguments only (no positional client arg).
    #
    # @param message [Message, Hash] the inbound message (raw parsed JSON or a Message)
    def receive(message)
      message = Message.coerce(message)
      dispatch(message.event, **message.params)
    end

    # Returns the default WebSocket URL derived from the current page location.
    # Only valid under Opal; raises on CRuby.
    #
    # @param path [String] the socket path segment
    # @return [String] e.g. +"wss://example.com/duoruby/socket"+
    # @raise [RuntimeError] when called outside Opal
    def self.default_socket_url(path = "/duoruby/socket")
      raise "default frontend transport is only available under Opal" unless RUBY_ENGINE == "opal"

      location = $window.location
      protocol = location.scheme == "https:" ? "wss:" : "ws:"
      "#{protocol}//#{location.host}#{path}"
    end

    # Returns the WebSocket class to use for connections.
    # Only valid under Opal; raises on CRuby.
    #
    # @return [Class] +Browser::Socket+ under Opal
    # @raise [RuntimeError] when called outside Opal
    def self.socket_class
      raise "default frontend transport is only available under Opal" unless RUBY_ENGINE == "opal"

      ::Browser::Socket
    end
  end
end
