# frozen_string_literal: true

require "spec_helper"
require "duoruby/setup/frontend"

RSpec.describe DuoRuby::Frontend do
  it "emits messages through a transport" do
    transported = []
    frontend = described_class.new { |message| transported << message }

    frontend.send(:join, room: "lobby")

    transported.should == [{"event" => "join", "params" => {"room" => "lobby"}}]
    frontend.sent.should == transported
  end

  it "keeps the default browser transport behind connect" do
    frontend = described_class.new

    -> { frontend.connect }.should raise_error(RuntimeError, "default frontend transport is only available under Opal")
  end

  it "dispatches lifecycle events from the default transport" do
    fake_socket_class = Class.new do
      attr_reader :url, :handlers, :written

      def initialize(url)
        @url = url
        @handlers = {}
        @written = []
      end

      def on(event, &block)
        handlers[event] = block
      end

      def write(message)
        written << message
      end

      def emit(event)
        handlers.fetch(event).call
      end
    end
    frontend_class = Class.new(described_class) do
      define_singleton_method(:socket_class) { fake_socket_class }
    end
    events = []
    frontend = frontend_class.new

    frontend.on(:$connect) { events << :connected }
    frontend.on(:$disconnect) { events << :disconnected }
    frontend.connect(url: "ws://example.test/duoruby/socket")
    frontend.socket.emit(:open)
    frontend.socket.emit(:close)

    frontend.socket.url.should == "ws://example.test/duoruby/socket"
    events.should == [:connected, :disconnected]
  end

  it "can reconnect with the same socket URL" do
    fake_socket_class = Class.new do
      attr_reader :url, :handlers

      def initialize(url)
        @url = url
        @handlers = {}
      end

      def on(event, &block)
        handlers[event] = block
      end

      def write(_message)
      end
    end
    frontend_class = Class.new(described_class) do
      define_singleton_method(:socket_class) { fake_socket_class }
    end
    events = []
    frontend = frontend_class.new

    frontend.on(:$reconnect) { events << :reconnected }
    frontend.connect(url: "ws://example.test/duoruby/socket")
    first_socket = frontend.socket
    frontend.reconnect

    frontend.socket.should_not equal(first_socket)
    frontend.socket.url.should == "ws://example.test/duoruby/socket"
    events.should == [:reconnected]
  end

  it "sends request messages and resolves call replies" do
    transported = []
    frontend = described_class.new { |message| transported << message }
    resolved = []

    promise = frontend.call(:load, id: 1)
    promise.then { |value| resolved << value }
    frontend.receive("event" => "$reply", "reply_to" => "call-1", "params" => {"result" => {"name" => "Alice"}})

    transported.should == [{"event" => "load", "params" => {"id" => 1}, "id" => "call-1"}]
    resolved.should == [{"name" => "Alice"}]
  end

  it "rejects call promises from structured errors" do
    transported = []
    frontend = described_class.new { |message| transported << message }
    rejected = []

    promise = frontend.call(:load)
    promise.fail { |error| rejected << error }
    frontend.receive(
      "event" => "$error",
      "reply_to" => "call-1",
      "params" => {"code" => "not_found", "message" => "Missing"}
    )

    rejected.should == [{code: "not_found", message: "Missing"}]
  end

  it "dispatches received messages to handlers" do
    received = []
    frontend = described_class.new

    frontend.on(:notice) { |text:| received << text }
    frontend.receive("event" => "notice", "params" => {"text" => "hello"})

    received.should == ["hello"]
  end

  it "supports class-level handlers for frontend subclasses" do
    frontend_class = Class.new(described_class) do
      attr_reader :received

      on(:notice) { |text:| received << text }

      def initialize
        super
        @received = []
      end
    end

    frontend = frontend_class.new
    frontend.receive("event" => "notice", "params" => {"text" => "hello"})

    frontend.received.should == ["hello"]
  end

  it "runs wildcard handlers for every event" do
    received = []
    frontend = described_class.new

    frontend.on(:*) { |event, text: nil| received << [event, text] }
    frontend.receive("event" => "notice", "params" => {"text" => "hello"})
    frontend.receive("event" => "ready", "params" => {})

    received.should == [["notice", "hello"], ["ready", nil]]
  end

  it "runs one-shot handlers once" do
    received = []
    frontend = described_class.new

    frontend.one(:notice) { |text:| received << text }
    frontend.receive("event" => "notice", "params" => {"text" => "first"})
    frontend.receive("event" => "notice", "params" => {"text" => "second"})

    received.should == ["first"]
  end

  it "removes handlers with off" do
    received = []
    frontend = described_class.new
    handler = proc { |text:| received << text }

    frontend.on(:notice, &handler)
    frontend.off(:notice, handler)
    frontend.receive("event" => "notice", "params" => {"text" => "hello"})

    received.should == []
    frontend.handlers.should == {}
  end

  it "returns handler tokens that off can remove" do
    received = []
    frontend = described_class.new

    first = frontend.on(:notice) { |text:| received << "first:#{text}" }
    frontend.on(:notice) { |text:| received << "second:#{text}" }
    frontend.off(first)
    frontend.trigger(:notice, text: "hello")

    received.should == ["second:hello"]
  end

  it "removes all event handlers by event name" do
    received = []
    frontend = described_class.new

    frontend.on(:notice) { |text:| received << "first:#{text}" }
    frontend.on(:notice) { |text:| received << "second:#{text}" }
    frontend.off(:notice)
    frontend.trigger(:notice, text: "hello")

    received.should == []
  end

  it "triggers handlers directly" do
    received = []
    frontend = described_class.new

    frontend.on(:notice) { |text:| received << text }
    frontend.trigger(:notice, text: "hello")

    received.should == ["hello"]
  end

  it "inherits handlers through subclass chains" do
    parent_class = Class.new(described_class) do
      attr_reader :received

      on(:notice) { |text:| received << text }

      def initialize
        super
        @received = []
      end
    end
    child_class = Class.new(parent_class)
    grandchild_class = Class.new(child_class)

    frontend = grandchild_class.new
    frontend.receive("event" => "notice", "params" => {"text" => "hello"})

    frontend.received.should == ["hello"]
  end

  it "inherits handlers from included modules" do
    first_module = Module.new do
      include DuoRuby::Channel::HandlerMethods

      on(:first) { received << :first }
    end
    second_module = Module.new do
      extend DuoRuby::Channel::HandlerMethods

      on(:second) { received << :second }
    end
    frontend_class = Class.new(described_class) do
      include first_module
      include second_module

      attr_reader :received

      def initialize
        super
        @received = []
      end
    end

    frontend = frontend_class.new
    frontend.trigger(:first)
    frontend.trigger(:second)

    frontend.received.should == [:first, :second]
  end

  it "clones class handlers into instances" do
    frontend_class = Class.new(described_class) do
      attr_reader :received

      on(:notice) { |text:| received << text }

      def initialize
        super
        @received = []
      end
    end
    first = frontend_class.new
    second = frontend_class.new

    first.off(:notice)
    first.on(:notice) { |text:| received << text.upcase }
    first.trigger(:notice, text: "hello")
    second.trigger(:notice, text: "hello")

    first.received.should == ["HELLO"]
    second.received.should == ["hello"]
    frontend_class.handlers["notice"].length.should == 1
  end

  it "supports namespaced channel handlers and sends" do
    transported = []
    received = []
    frontend = described_class.new { |message| transported << message }

    frontend.channel(:chat).on(:message) { |text:| received << text }
    frontend.channel(:chat).send(:join, room: "lobby")
    frontend.receive("event" => "chat:message", "params" => {"text" => "hello"})

    transported.should == [{"event" => "chat:join", "params" => {"room" => "lobby"}}]
    received.should == ["hello"]
  end
end
