# frozen_string_literal: true

require "spec_helper"
require "duoruby/setup/backend"

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

  it "supports namespaced server channels" do
    server_class = Class.new(described_class) do
      channel(:chat).on(:join) { |client, room:| group(room) << client }
    end
    server = server_class.new
    client = server.connect(id: "client-1") {}

    server.receive(client, "event" => "chat:join", "params" => {"room" => "lobby"})

    server.group(:lobby).members.should == [client]
  end
end
