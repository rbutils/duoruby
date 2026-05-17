# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "duoruby/server"

RSpec.describe DuoRuby::Server do
  class ServerLaunchProbe < described_class
    attr_reader :events

    def initialize(**options)
      super
      @events = []
    end

    private

    def fork_process
      @events << :fork_browser
      yield
      1234
    end

    def start_browser_watchdog(pid)
      @events << [:watch_browser, pid]
      nil
    end

    def run_browser(**)
      @events << :run_browser
    end

    def run(output: $stdout)
      @events << [:run_server, output.path]
    end

    def terminate_process(pid)
      @events << [:terminate_browser, pid]
    end
  end

  it "runs the server in the main process and the browser in the forked child" do
    output = StringIO.new
    server = ServerLaunchProbe.new(port: 4567)

    server.launch(output: output)

    output.string.should include("launching http://127.0.0.1:4567")
    server.events.should == [
      :fork_browser,
      :run_browser,
      [:watch_browser, 1234],
      [:run_server, File::NULL],
      [:terminate_browser, 1234]
    ]
  end

  it "terminates the browser child when the server exits with an error" do
    probe_class = Class.new(ServerLaunchProbe) do
      private

      def run(output: $stdout)
        @events << [:run_server, output.path]
        raise "server failed"
      end
    end
    server = probe_class.new(port: 4567)

    -> { server.launch(output: StringIO.new) }.should raise_error(RuntimeError, "server failed")

    server.events.should include([:terminate_browser, 1234])
  end

end
