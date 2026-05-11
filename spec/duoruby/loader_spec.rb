# frozen_string_literal: true

require "spec_helper"
require "duoruby"

RSpec.describe "duoruby loader" do
  it "loads the backend setup on CRuby" do
    defined?(DuoRuby::Backend).should == "constant"
    DuoRuby.respond_to?(:backend).should == true
  end
end
