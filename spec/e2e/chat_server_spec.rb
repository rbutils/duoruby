# frozen_string_literal: true

require "spec_helper"
require "async"
require "async/http/endpoint"
require "async/websocket/client"
require "falcon/server"
require "json"
require "socket"
require "duoruby/server"

RSpec.describe "sample chat server" do
  let(:root) { File.expand_path("../../examples/chat", __dir__) }

  def available_port
    server = TCPServer.new("127.0.0.1", 0)
    server.addr[1]
  ensure
    server&.close
  end

  def send_message(connection, event, **params)
    connection.send_text(JSON.generate("event" => event.to_s, "params" => params.transform_keys(&:to_s)))
    connection.flush
  end

  def read_message(connection)
    JSON.parse(connection.read)
  end

  it "lets two WebSocket clients chat through the sample backend" do
    port = available_port
    app = DuoRuby::Server.build(root: root, port: port)
    endpoint = Async::HTTP::Endpoint.parse("http://127.0.0.1:#{port}")
    websocket_endpoint = Async::HTTP::Endpoint.parse("ws://127.0.0.1:#{port}/duoruby/socket")

    Sync do |task|
      server_task = Falcon::Server.new(app, endpoint).run
      task.sleep(0.05)

      alice = Async::WebSocket::Client.connect(websocket_endpoint)
      bob = Async::WebSocket::Client.connect(websocket_endpoint)

      send_message(alice, :join, room: "lobby", name: "Alice")
      read_message(alice).should == {
        "event" => "snapshot",
        "params" => {"room" => "lobby", "name" => "Alice", "rooms" => ["lobby", "help", "random"], "users" => ["Alice"], "history" => []}
      }
      read_message(alice).should == {"event" => "presence", "params" => {"room" => "lobby", "users" => ["Alice"]}}
      read_message(alice).should == {"event" => "system", "params" => {"room" => "lobby", "text" => "Alice joined lobby"}}

      send_message(bob, :join, room: "lobby", name: "Bob")
      read_message(bob).should == {
        "event" => "snapshot",
        "params" => {
          "room" => "lobby",
          "name" => "Bob",
          "rooms" => ["lobby", "help", "random"],
          "users" => ["Alice", "Bob"],
          "history" => [{"name" => "system", "text" => "Alice joined lobby"}]
        }
      }
      read_message(alice).should == {"event" => "presence", "params" => {"room" => "lobby", "users" => ["Alice", "Bob"]}}
      read_message(bob).should == {"event" => "presence", "params" => {"room" => "lobby", "users" => ["Alice", "Bob"]}}
      read_message(alice).should == {"event" => "system", "params" => {"room" => "lobby", "text" => "Bob joined lobby"}}
      read_message(bob).should == {"event" => "system", "params" => {"room" => "lobby", "text" => "Bob joined lobby"}}

      send_message(alice, :speak, room: "lobby", text: "hello")
      read_message(alice).should == {"event" => "message", "params" => {"room" => "lobby", "name" => "Alice", "text" => "hello"}}
      read_message(bob).should == {"event" => "message", "params" => {"room" => "lobby", "name" => "Alice", "text" => "hello"}}

      send_message(bob, :join, room: "help", name: "Bob")
      read_message(alice).should == {"event" => "presence", "params" => {"room" => "lobby", "users" => ["Alice"]}}
      read_message(alice).should == {"event" => "system", "params" => {"room" => "lobby", "text" => "Bob left lobby"}}
      read_message(bob).should == {
        "event" => "snapshot",
        "params" => {"room" => "help", "name" => "Bob", "rooms" => ["lobby", "help", "random"], "users" => ["Bob"], "history" => []}
      }
      read_message(bob).should == {"event" => "presence", "params" => {"room" => "help", "users" => ["Bob"]}}
      read_message(bob).should == {"event" => "system", "params" => {"room" => "help", "text" => "Bob joined help"}}
    ensure
      alice&.close
      bob&.close
      server_task&.stop
    end
  end
end
