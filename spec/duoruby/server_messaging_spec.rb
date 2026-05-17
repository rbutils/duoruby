# frozen_string_literal: true

require "spec_helper"
require "duoruby/setup/backend"
require "duoruby/socket"

RSpec.describe DuoRuby::Server do
  it "broadcasts messages to grouped clients" do
    server = described_class.new
    delivered = []
    client = server.connect(id: "client-1") { |message| delivered << message }

    server.group(:admins).add client
    server.group(:admins).send :notice, text: "hello"

    delivered.should == [{"event" => "notice", "params" => {"text" => "hello"}}]
  end

  it "runs message handlers with the client and params" do
    server = described_class.new
    client = server.connect(id: "client-1") {}

    server.on(:join) { |connected_client, room:| server.group(room).add(connected_client) }
    server.receive(client, "event" => "join", "params" => {"room" => "lobby"})

    server.group(:lobby).members.should == [client]
  end

  it "supports class-level handlers for server subclasses" do
    server_class = Class.new(described_class) do
      on(:join) { |connected_client, room:| group(room).add(connected_client) }
    end

    server = server_class.new
    client = server.connect(id: "client-1") {}
    server.receive(client, "event" => "join", "params" => {"room" => "lobby"})

    server.group(:lobby).members.should == [client]
  end

  it "supports shovel group membership" do
    server = described_class.new
    client = server.connect(id: "client-1") {}

    server.group(:lobby) << client

    server.group(:lobby).members.should == [client]
  end

  it "supports group targeting and membership helpers" do
    server = described_class.new
    alice_messages = []
    bob_messages = []
    alice = server.connect(id: "alice") { |message| alice_messages << message }
    bob = server.connect(id: "bob") { |message| bob_messages << message }
    group = server.group(:lobby)

    alice.join(group)
    bob.join(group)
    group.send_to_others(alice, :notice, text: "hello")

    group.include?(alice).should == true
    group.size.should == 2
    group.empty?.should == false
    alice_messages.should == []
    bob_messages.should == [{"event" => "notice", "params" => {"text" => "hello"}}]
    bob.leave(group)
    group.members.should == [alice]
  end

  it "runs connection lifecycle handlers" do
    server_class = Class.new(described_class) do
      on(:$connect) { |connected_client| connected_client[:connected] = true }
      on(:$disconnect) { |connected_client| connected_client[:connected] = false }
    end

    server = server_class.new
    client = server.connect(id: "client-1") {}

    client[:connected].should == true

    server.disconnect(client)

    client[:connected].should == false
  end

  it "stores application-level client attributes" do
    client = described_class.new.connect(id: "client-1") {}

    client[:name] = "Alice"

    client[:name].should == "Alice"
    client.attributes.should == {name: "Alice"}
  end

  it "passes connection metadata and can reject authentication" do
    server_class = Class.new(described_class) do
      def authenticate(client)
        client.metadata[:token] == "secret"
      end
    end
    server = server_class.new
    rejected_messages = []

    rejected = server.connect(id: "bad", metadata: {token: "no"}) { |message| rejected_messages << message }
    accepted = server.connect(id: "good", metadata: {token: "secret"}) {}

    rejected.accepted?.should == false
    accepted.accepted?.should == true
    accepted.metadata.should == {token: "secret"}
    rejected_messages.should == [
      {"event" => "$error", "params" => {"code" => "unauthorized", "message" => "connection rejected"}}
    ]
  end

  it "replies to request messages with handler return values" do
    server = described_class.new
    delivered = []
    client = server.connect(id: "client-1") { |message| delivered << message }

    server.on(:load) { |_client, id:| {id: id, name: "Alice"} }
    server.receive(client, "event" => "load", "id" => "call-1", "params" => {"id" => 1})

    delivered.should == [
      {"event" => "$reply", "params" => {"result" => {id: 1, name: "Alice"}}, "reply_to" => "call-1"}
    ]
  end

  it "sends structured errors when request handlers fail" do
    server = described_class.new
    delivered = []
    client = server.connect(id: "client-1") { |message| delivered << message }

    server.on(:load) { raise ArgumentError, "bad id" }
    server.receive(client, "event" => "load", "id" => "call-1", "params" => {})

    delivered.should == [
      {"event" => "$error", "params" => {"code" => "ArgumentError", "message" => "bad id"}, "reply_to" => "call-1"}
    ]
  end

  it "lets server client question sends await socket handler replies" do
    server = described_class.new
    client = nil
    socket = DuoRuby::Socket.new { |message| server.receive(client, message) }
    socket.on(:name?) { "Alice" }
    client = server.connect(id: "client-1") { |message| socket.receive(message) }

    promise = client.send(:name?)
    values = []
    promise.then { |value| values << value }

    promise.should be_a(DuoRuby::ReplyPromise)
    promise.await.should == "Alice"
    promise.__await__.should == "Alice"
    values.should == ["Alice"]
  end

  it "rejects server client question sends when socket handlers fail" do
    server = described_class.new
    client = nil
    socket = DuoRuby::Socket.new { |message| server.receive(client, message) }
    socket.on(:name?) { raise ArgumentError, "missing name" }
    client = server.connect(id: "client-1") { |message| socket.receive(message) }

    promise = client.send(:name?)
    errors = []
    promise.fail { |error| errors << error }

    lambda { promise.await }.should raise_error(DuoRuby::ReplyError, "missing name")
    errors.first.code.should == "ArgumentError"
  end

  it "rejects pending server client questions on disconnect" do
    server = described_class.new
    client = server.connect(id: "client-1") {}

    promise = client.send(:name?)
    server.disconnect(client)

    lambda { promise.await }.should raise_error(DuoRuby::ReplyError, "connection closed")
    promise.value.code.should == "disconnect"
  end

  it "returns reply promise collections for group question sends" do
    server = described_class.new
    alice = nil
    bob = nil
    alice_socket = DuoRuby::Socket.new { |message| server.receive(alice, message) }
    bob_socket = DuoRuby::Socket.new { |message| server.receive(bob, message) }
    alice_socket.on(:name?) { "Alice" }
    bob_socket.on(:name?) { "Bob" }
    alice = server.connect(id: "alice") { |message| alice_socket.receive(message) }
    bob = server.connect(id: "bob") { |message| bob_socket.receive(message) }
    group = server.group(:lobby)

    alice.join(group)
    bob.join(group)

    promises = group.send(:name?)

    promises.map(&:await).should == ["Alice", "Bob"]
    group.except(alice).send(:name?).map(&:await).should == ["Bob"]
  end

  it "supports namespaced sends from clients and groups" do
    server = described_class.new
    client = nil
    socket = DuoRuby::Socket.new { |message| server.receive(client, message) }
    delivered = []
    socket.channel(:game).on(:ready?) { {ready: true} }
    socket.channel(:game).on(:state) { |value:| delivered << value }
    client = server.connect(id: "client-1") { |message| socket.receive(message) }
    group = server.group(:players)
    group << client

    client.channel(:game).send(:state, value: "joined")
    replies = group.channel(:game).send(:ready?)

    delivered.should == ["joined"]
    replies.map(&:await).should == [{ready: true}]
  end

  it "supports block-style namespaced sends from clients, groups, and selections" do
    server = described_class.new
    client = nil
    socket = DuoRuby::Socket.new { |message| server.receive(client, message) }
    delivered = []
    socket.channel(:game) do
      on(:ready?) { {ready: true} }
      on(:state) { |value:| delivered << value }
    end
    client = server.connect(id: "client-1") { |message| socket.receive(message) }
    group = server.group(:players)
    group << client

    client.channel(:game) { send(:state, value: "joined") }
    group_replies = group.channel(:game) { send(:ready?) }
    selection_replies = group.except.channel(:game) { send(:ready?) }

    delivered.should == ["joined"]
    group_replies.map(&:await).should == [{ready: true}]
    selection_replies.map(&:await).should == [{ready: true}]
  end

  it "supports yielded namespaced sends from clients, groups, and selections" do
    server = described_class.new
    client = nil
    socket = DuoRuby::Socket.new { |message| server.receive(client, message) }
    delivered = []
    socket.channel(:game) do |game|
      game.on(:ready?) { {ready: true} }
      game.on(:state) { |value:| delivered << value }
    end
    client = server.connect(id: "client-1") { |message| socket.receive(message) }
    group = server.group(:players)
    group << client

    client.channel(:game) { |game| game.send(:state, value: "joined") }
    group_replies = group.channel(:game) { |game| game.send(:ready?) }
    selection_replies = group.except.channel(:game) { |game| game.send(:ready?) }

    delivered.should == ["joined"]
    group_replies.map(&:await).should == [{ready: true}]
    selection_replies.map(&:await).should == [{ready: true}]
  end

  it "supports namespaced server channels" do
    server_class = Class.new(described_class) do
      channel(:chat).on(:join) { |client, room:| group(room) << client }
    end
    server = server_class.new
    client = server.connect(id: "client-1") {}

    server.receive(client, "event" => "chat:join", "params" => {"room" => "lobby"})

    server.group(:lobby).members.should == [client]
  end

  it "supports block-style namespaced server channels" do
    server_class = Class.new(described_class) do
      channel(:chat) do
        on(:join) { |client, room:| group(room) << client }
      end
    end
    server = server_class.new
    client = server.connect(id: "client-1") {}

    server.receive(client, "event" => "chat:join", "params" => {"room" => "lobby"})

    server.group(:lobby).members.should == [client]
  end

  it "supports yielded namespaced server channels" do
    server_class = Class.new(described_class) do
      channel(:chat) do |chat|
        chat.on(:join) { |client, room:| group(room) << client }
      end
    end
    server = server_class.new
    client = server.connect(id: "client-1") {}

    server.receive(client, "event" => "chat:join", "params" => {"room" => "lobby"})

    server.group(:lobby).members.should == [client]
  end
end
