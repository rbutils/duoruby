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
    class TestPromise
      attr_reader :value, :error

      def initialize
        @resolved = false
        @rejected = false
        @then_handlers = []
        @fail_handlers = []
      end

      def resolve(value = nil)
        @resolved = true
        @value = value
        @then_handlers.each { |handler| handler.call(value) }
        self
      end

      def reject(error = nil)
        @rejected = true
        @error = error
        @fail_handlers.each { |handler| handler.call(error) }
        self
      end

      def then(&handler)
        @resolved ? handler.call(value) : @then_handlers << handler
        self
      end

      def fail(&handler)
        @rejected ? handler.call(error) : @fail_handlers << handler
        self
      end

      alias_method :rescue, :fail
    end

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
    def connect(url: nil, path: "/duoruby/socket", reconnect: false, backoff: 1)
      raise "already connected" if @socket

      @connect_url = url || self.class.default_socket_url(path)
      @reconnect = reconnect
      @reconnect_backoff = backoff
      open_socket
      self
    end

    def reconnect
      @socket = nil
      open_socket
      trigger(:$reconnect)
      self
    end

    def open_socket
      @socket = self.class.socket_class.new(@connect_url)
      @transport = proc { |message| socket.write(JSON.generate(message)) }

      socket.on(:open) { trigger(:$connect) }
      socket.on(:message) { |event| receive(JSON.parse(event.data)) }
      socket.on(:close) do
        trigger(:$disconnect)
        schedule_reconnect if @reconnect
      end
    end

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

    def schedule_reconnect
      if RUBY_ENGINE == "opal"
        $window.set_timeout(proc { reconnect }, @reconnect_backoff * 1000)
      end
    end
  end
end
