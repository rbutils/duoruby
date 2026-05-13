# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "duoruby/setup/backend"
require "duoruby/cli"

RSpec.describe DuoRuby::CLI do
  it "writes help to the provided output" do
    output = StringIO.new

    status = described_class.new(["help"], input: StringIO.new, output: output).call

    status.should == 0
    output.string.should include("duoruby serve")
    output.string.should_not include("frontend")
    output.string.should_not include("boot")
  end

  it "reports invalid serve ports" do
    output = StringIO.new

    status = described_class.new(["serve", "--port", "abc"], input: StringIO.new, output: output).call

    status.should == 1
    output.string.should include("invalid serve port: abc")
  end

  it "includes launch in help output" do
    output = StringIO.new

    status = described_class.new(["help"], input: StringIO.new, output: output).call

    status.should == 0
    output.string.should include("duoruby launch")
  end

  it "reports invalid launch ports" do
    output = StringIO.new

    status = described_class.new(["launch", "--port", "0"], input: StringIO.new, output: output).call

    status.should == 1
    output.string.should include("invalid serve port: 0")
  end

  it "reports unknown launch options" do
    output = StringIO.new

    status = described_class.new(["launch", "--unknown"], input: StringIO.new, output: output).call

    status.should == 1
    output.string.should include("unknown launch option")
  end
end
