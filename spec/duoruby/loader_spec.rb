# frozen_string_literal: true

require "spec_helper"
require "duoruby"

RSpec.describe "duoruby loader" do
  it "loads the server setup on CRuby" do
    defined?(DuoRuby::Server).should == "constant"
    DuoRuby.respond_to?(:server).should == true
  end
end
