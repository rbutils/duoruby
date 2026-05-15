# frozen_string_literal: true

require "spec_helper"
require "duoruby/setup/backend"
require "duoruby/setup/frontend"

RSpec.describe "ready room example" do
  let(:root) { File.expand_path("../../examples/ready_room", __dir__) }

  def load_ready_room_app
    DuoRuby.boot(:backend, root: root)
    require "ready_room/socket"
  end

  def connect(server, socket, id)
    client = nil
    socket.transport = proc { |message| server.receive(client, message) }
    client = server.connect(id: id) { |message| socket.receive(message) }
    client
  end

  it "uses namespaced questions for readiness, state sync, voting, and scoring" do
    load_ready_room_app
    server = ReadyRoom::Server.new
    alice_socket = ReadyRoom::Socket.new(name: "Alice", ready: true, vote: "Bob")
    bob_socket = ReadyRoom::Socket.new(name: "Bob", ready: false, vote: "Alice")
    connect(server, alice_socket, "alice")
    connect(server, bob_socket, "bob")

    alice_socket.join
    bob_socket.join
    alice_socket.mark_ready(true)

    rejected = []
    alice_socket.start_round.fail { |error| rejected << error }
    rejected.first.should be_a(DuoRuby::ReplyError)
    rejected.first.code.should == "ArgumentError"
    rejected.first.message.should == "waiting for Bob"

    bob_socket.mark_ready(true)
    started = []
    alice_socket.start_round.then { |state| started << state }
    started.first.fetch("ready").should == {"Alice" => true, "Bob" => true}
    alice_socket.events.should include("round: #{ReadyRoom.prompt}")
    bob_socket.events.should include("round: #{ReadyRoom.prompt}")

    alice_socket.answer("Hash")
    bob_socket.answer("Mutex")

    scores = []
    alice_socket.score.then { |scoreboard| scores << scoreboard }
    scores.first.should == [
      {"name" => "Alice", "text" => "Hash", "votes" => 1},
      {"name" => "Bob", "text" => "Mutex", "votes" => 1}
    ]

    state = []
    alice_socket.state.then { |value| state << value }
    state.first.fetch("you").should == "Alice"
    state.first.fetch("scoreboard").should == scores.first
  end

  it "resyncs state on reconnect and reports structured validation errors" do
    load_ready_room_app
    server = ReadyRoom::Server.new
    alice_socket = ReadyRoom::Socket.new(name: "Alice", ready: true)
    duplicate_socket = ReadyRoom::Socket.new(name: "Alice")
    connect(server, alice_socket, "alice")
    connect(server, duplicate_socket, "duplicate")

    alice_socket.join

    errors = []
    duplicate_socket.join.fail { |error| errors << error }
    errors.first.should be_a(DuoRuby::ReplyError)
    errors.first.message.should == "name is already taken"

    alice_socket.trigger(:$reconnect)
    alice_socket.events.should include("resynced")
    alice_socket.states.last.fetch("you").should == "Alice"
  end
end
