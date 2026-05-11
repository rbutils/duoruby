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
end
