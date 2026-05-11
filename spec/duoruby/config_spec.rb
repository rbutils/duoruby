# frozen_string_literal: true

require "spec_helper"
require "duoruby/config"

RSpec.describe DuoRuby::Config do
  after { DuoRuby.instance_variable_set(:@config, nil) }

  it "has a default title of DuoRuby" do
    DuoRuby.config.title.should == "DuoRuby"
  end

  it "allows the title to be changed via configure" do
    DuoRuby.configure { |c| c.title = "My App" }

    DuoRuby.config.title.should == "My App"
  end

  it "persists configuration across multiple accesses" do
    DuoRuby.configure { |c| c.title = "Persistent" }

    DuoRuby.config.title.should == "Persistent"
    DuoRuby.config.title.should == "Persistent"
  end

  it "has nil host and port by default" do
    DuoRuby.config.host.should be_nil
    DuoRuby.config.port.should be_nil
  end

  it "allows host and port to be set" do
    DuoRuby.config.host = "0.0.0.0"
    DuoRuby.config.port = 4000

    DuoRuby.config.host.should == "0.0.0.0"
    DuoRuby.config.port.should == 4000
  end
end
