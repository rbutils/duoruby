# frozen_string_literal: true

require "spec_helper"
require "duoruby/setup/backend"
require "duoruby/setup/frontend"
require "duoruby/testing"

RSpec.describe "in-memory client/server flow" do
  it "lets frontend messages drive backend group broadcast" do
    backend = DuoRuby.backend do
      on(:join) { |client, room:| group(room) << client }
      on(:say) { |_client, room:, text:| group(room).send :said, text: text }
    end

    delivered = []
    client = backend.connect(id: "client-1") { |message| delivered << message }
    frontend = DuoRuby::Frontend.new { |message| backend.receive(client, message) }

    frontend.send(:join, room: "lobby")
    frontend.send(:say, room: "lobby", text: "hello")

    delivered.should == [{"event" => "said", "params" => {"text" => "hello"}}]
  end

  it "wires a backend and frontend with the test harness" do
    backend = DuoRuby.backend do
      on(:ping) { "pong" }
    end
    connection = DuoRuby::Testing.connect(backend: backend)
    resolved = []

    connection.frontend.call(:ping).then { |value| resolved << value }

    resolved.should == ["pong"]
  end
end
