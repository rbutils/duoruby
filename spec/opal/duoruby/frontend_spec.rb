# frozen_string_literal: true

require "spec_helper"
require "duoruby/frontend"

RSpec.describe DuoRuby::Frontend do
  it "emits messages in Opal" do
    transported = []
    frontend = described_class.new { |message| transported << message }

    frontend.send(:join, room: "lobby")

    transported.should == [{"event" => "join", "params" => {"room" => "lobby"}}]
  end

  it "dispatches class-level handlers with params in Opal" do
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

  it "dispatches wildcard handlers in Opal" do
    received = []
    frontend = described_class.new

    frontend.on(:*) { |event, text: nil| received << [event, text] }
    frontend.receive("event" => "notice", "params" => {"text" => "hello"})

    received.should == [["notice", "hello"]]
  end

  it "dispatches one-shot handlers once in Opal" do
    received = []
    frontend = described_class.new

    frontend.one(:notice) { |text:| received << text }
    frontend.receive("event" => "notice", "params" => {"text" => "first"})
    frontend.receive("event" => "notice", "params" => {"text" => "second"})

    received.should == ["first"]
  end

  it "removes returned handler tokens in Opal" do
    received = []
    frontend = described_class.new

    first = frontend.on(:notice) { |text:| received << "first:#{text}" }
    frontend.on(:notice) { |text:| received << "second:#{text}" }
    frontend.off(first)
    frontend.trigger(:notice, text: "hello")

    received.should == ["second:hello"]
  end
end
