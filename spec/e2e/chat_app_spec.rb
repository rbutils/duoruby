# frozen_string_literal: true

require "spec_helper"
require "duoruby/setup/backend"
require "duoruby/setup/frontend"

RSpec.describe "sample chat app" do
  let(:root) { File.expand_path("../../examples/chat", __dir__) }

  def load_chat_app
    DuoRuby.boot(:backend, root: root)
    require "chat/socket"
  end

  it "supports room history, presence, room switching, and chat messages" do
    load_chat_app
    server = Chat::Server.new

    alice = nil
    bob = nil
    alice_socket = Chat::Socket.new { |message| server.receive(alice, message) }
    bob_socket = Chat::Socket.new { |message| server.receive(bob, message) }
    alice = server.connect(id: "alice") { |message| alice_socket.receive(message) }
    bob = server.connect(id: "bob") { |message| bob_socket.receive(message) }

    alice_socket.send(:join, room: "lobby", name: "Alice")
    bob_socket.send(:join, room: "lobby", name: "Bob")
    alice_socket.send(:speak, room: "lobby", text: "hello")
    bob_socket.send(:join, room: "help", name: "Bob")
    bob_socket.send(:speak, room: "help", text: "anyone here?")

    alice_socket.log.entries.should == [
      "Alice joined lobby",
      "Bob joined lobby",
      "Alice: hello",
      "Bob left lobby"
    ]
    bob_socket.log.entries.should == ["Bob joined help", "Bob: anyone here?"]
    server.users("lobby").should == ["Alice"]
    server.users("help").should == ["Bob"]
    server.history["lobby"].map { |entry| entry.fetch("text") }.should include("Alice joined lobby", "hello", "Bob left lobby")
  end

  it "creates custom rooms from user input" do
    load_chat_app
    server = Chat::Server.new
    socket = nil
    client = nil
    socket = Chat::Socket.new { |message| server.receive(client, message) }
    client = server.connect(id: "client") { |message| socket.receive(message) }

    socket.send(:join, room: "New Room", name: "Alice")
    socket.send(:speak, room: "new-room", text: "hello")

    server.rooms.should include("new-room")
    server.users("new-room").should == ["Alice"]
    server.history["new-room"].map { |entry| entry.fetch("text") }.should include("Alice joined new-room", "hello")
  end
end
