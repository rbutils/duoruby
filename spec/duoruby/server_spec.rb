# frozen_string_literal: true

require "spec_helper"
require "duoruby/server"
require "glimmer-dsl-web"

RSpec.describe DuoRuby::Server do
  after { DuoRuby.instance_variable_set(:@config, nil) }

  let(:chat_root) { File.expand_path("../../examples/chat", __dir__) }
  let(:counter_root) { File.expand_path("../../examples/glimmer_counter", __dir__) }

  it "serves a root page that loads the frontend script" do
    response = described_class.new(root: chat_root).call(Protocol::HTTP::Request["GET", "/"])
    body = response.read

    response.status.should == 200
    body.should include("/duoruby/app.js")
    body.should include("duoruby-root")
    body.should_not include("duoruby-chat")
  end

  it "compiles the chat sample frontend setup for the browser" do
    javascript = described_class.new(root: chat_root).frontend_javascript

    javascript.should include("global_object.Opal")
    javascript.should include("'$default_room'")
    javascript.should include("DuoRuby team chat")
    javascript.should include("'$history_limit'")
    javascript.should include("/duoruby/socket")
    javascript.should include("$connect")
    javascript.should include("$socket_class")
    javascript.should_not include("window.location")
  end

  it "compiles the glimmer counter frontend including Opal, glimmer, and Counter" do
    javascript = described_class.new(root: counter_root).frontend_javascript

    javascript.should include("global_object.Opal")
    javascript.should include("Glimmer")
    javascript.should include("Counter")
    javascript.should include("/duoruby/socket")
  end
end
