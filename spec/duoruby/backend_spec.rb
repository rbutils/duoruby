# frozen_string_literal: true

require "spec_helper"
require "duoruby/backend/setup"

RSpec.describe DuoRuby::Backend do
  it "broadcasts messages to grouped clients" do
    backend = described_class.new
    delivered = []
    client = backend.connect(id: "client-1") { |message| delivered << message }

    backend.group(:admins).add client
    backend.group(:admins).send :notice, text: "hello"

    delivered.should == [{"event" => "notice", "params" => {"text" => "hello"}}]
  end

  it "runs message handlers with the client and params" do
    backend = described_class.new
    client = backend.connect(id: "client-1") {}

    backend.on(:join) { |connected_client, room:| backend.group(room).add(connected_client) }
    backend.receive(client, "event" => "join", "params" => {"room" => "lobby"})

    backend.group(:lobby).members.should == [client]
  end

  it "supports class-level handlers for backend subclasses" do
    backend_class = Class.new(described_class) do
      on(:join) { |connected_client, room:| group(room).add(connected_client) }
    end

    backend = backend_class.new
    client = backend.connect(id: "client-1") {}
    backend.receive(client, "event" => "join", "params" => {"room" => "lobby"})

    backend.group(:lobby).members.should == [client]
  end

  it "supports shovel group membership" do
    backend = described_class.new
    client = backend.connect(id: "client-1") {}

    backend.group(:lobby) << client

    backend.group(:lobby).members.should == [client]
  end

  it "supports group targeting and membership helpers" do
    backend = described_class.new
    alice_messages = []
    bob_messages = []
    alice = backend.connect(id: "alice") { |message| alice_messages << message }
    bob = backend.connect(id: "bob") { |message| bob_messages << message }
    group = backend.group(:lobby)

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
    backend_class = Class.new(described_class) do
      on(:$connect) { |connected_client| connected_client[:connected] = true }
      on(:$disconnect) { |connected_client| connected_client[:connected] = false }
    end

    backend = backend_class.new
    client = backend.connect(id: "client-1") {}

    client[:connected].should == true

    backend.disconnect(client)

    client[:connected].should == false
  end

  it "stores application-level client attributes" do
    client = described_class.new.connect(id: "client-1") {}

    client[:name] = "Alice"

    client[:name].should == "Alice"
    client.attributes.should == {name: "Alice"}
  end

  it "passes connection metadata and can reject authentication" do
    backend_class = Class.new(described_class) do
      def authenticate(client)
        client.metadata[:token] == "secret"
      end
    end
    backend = backend_class.new
    rejected_messages = []

    rejected = backend.connect(id: "bad", metadata: {token: "no"}) { |message| rejected_messages << message }
    accepted = backend.connect(id: "good", metadata: {token: "secret"}) {}

    rejected.accepted?.should == false
    accepted.accepted?.should == true
    accepted.metadata.should == {token: "secret"}
    rejected_messages.should == [
      {"event" => "$error", "params" => {"code" => "unauthorized", "message" => "connection rejected"}}
    ]
  end

  it "replies to request messages with handler return values" do
    backend = described_class.new
    delivered = []
    client = backend.connect(id: "client-1") { |message| delivered << message }

    backend.on(:load) { |_client, id:| {id: id, name: "Alice"} }
    backend.receive(client, "event" => "load", "id" => "call-1", "params" => {"id" => 1})

    delivered.should == [
      {"event" => "$reply", "params" => {"result" => {id: 1, name: "Alice"}}, "reply_to" => "call-1"}
    ]
  end

  it "sends structured errors when request handlers fail" do
    backend = described_class.new
    delivered = []
    client = backend.connect(id: "client-1") { |message| delivered << message }

    backend.on(:load) { raise ArgumentError, "bad id" }
    backend.receive(client, "event" => "load", "id" => "call-1", "params" => {})

    delivered.should == [
      {"event" => "$error", "params" => {"code" => "ArgumentError", "message" => "bad id"}, "reply_to" => "call-1"}
    ]
  end

  it "supports namespaced backend channels" do
    backend_class = Class.new(described_class) do
      channel(:chat).on(:join) { |client, room:| group(room) << client }
    end
    backend = backend_class.new
    client = backend.connect(id: "client-1") {}

    backend.receive(client, "event" => "chat:join", "params" => {"room" => "lobby"})

    backend.group(:lobby).members.should == [client]
  end
end
