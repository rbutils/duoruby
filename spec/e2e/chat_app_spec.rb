# frozen_string_literal: true

require "spec_helper"
require "duoruby/setup/backend"
require "duoruby/setup/frontend"

RSpec.describe "sample chat app" do
  let(:root) { File.expand_path("../../examples/chat", __dir__) }

  def load_chat_app
    DuoRuby.boot(:backend, root: root)
    require "chat/frontend"
  end

  it "supports room history, presence, room switching, and chat messages" do
    load_chat_app
    backend = Chat::Backend.new

    alice = nil
    bob = nil
    alice_frontend = Chat::Frontend.new { |message| backend.receive(alice, message) }
    bob_frontend = Chat::Frontend.new { |message| backend.receive(bob, message) }
    alice = backend.connect(id: "alice") { |message| alice_frontend.receive(message) }
    bob = backend.connect(id: "bob") { |message| bob_frontend.receive(message) }

    alice_frontend.send(:join, room: "lobby", name: "Alice")
    bob_frontend.send(:join, room: "lobby", name: "Bob")
    alice_frontend.send(:speak, room: "lobby", text: "hello")
    bob_frontend.send(:join, room: "help", name: "Bob")
    bob_frontend.send(:speak, room: "help", text: "anyone here?")

    alice_frontend.log.entries.should == [
      "Alice joined lobby",
      "Bob joined lobby",
      "Alice: hello",
      "Bob left lobby"
    ]
    bob_frontend.log.entries.should == ["Bob joined help", "Bob: anyone here?"]
    backend.users("lobby").should == ["Alice"]
    backend.users("help").should == ["Bob"]
    backend.history["lobby"].map { |entry| entry.fetch("text") }.should include("Alice joined lobby", "hello", "Bob left lobby")
  end

  it "creates custom rooms from user input" do
    load_chat_app
    backend = Chat::Backend.new
    frontend = nil
    client = nil
    frontend = Chat::Frontend.new { |message| backend.receive(client, message) }
    client = backend.connect(id: "client") { |message| frontend.receive(message) }

    frontend.send(:join, room: "New Room", name: "Alice")
    frontend.send(:speak, room: "new-room", text: "hello")

    backend.rooms.should include("new-room")
    backend.users("new-room").should == ["Alice"]
    backend.history["new-room"].map { |entry| entry.fetch("text") }.should include("Alice joined new-room", "hello")
  end
end
