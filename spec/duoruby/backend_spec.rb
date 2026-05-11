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
end
