# frozen_string_literal: true

require "socket"
require "duoruby/config"

module DuoRuby
  # Starts the server in the main process and opens a native webview window
  # in a forked child process.
  #
  # The server is the application owner; the browser window is a client. The
  # webview library is required inside the child, after +fork+, so native GUI
  # state is initialized in the process that owns the window.
  #
  # The window title defaults to +DuoRuby.config.title+, which the application
  # can set in its +duoruby.rb+ config file:
  #
  #   DuoRuby.configure { |c| c.title = "My App" }
  #
  # @example
  #   DuoRuby::Launcher.new(root: __dir__).run
  class Launcher
    # @param root   [String]       application root directory
    # @param host   [String]       server host (default: +"127.0.0.1"+)
    # @param port   [Integer, nil] server port; +nil+ picks a free port automatically
    # @param title  [String, nil]  window title; +nil+ uses +DuoRuby.config.title+
    # @param width  [Integer]      window width in pixels (default: +1280+)
    # @param height [Integer]      window height in pixels (default: +800+)
    def initialize(root: Dir.pwd, host: "127.0.0.1", port: nil,
                   title: nil, width: 1280, height: 800)
      @root   = File.expand_path(root)
      @host   = host
      @port   = port || free_port
      @title  = title
      @width  = width
      @height = height
    end

    # Forks the native browser into a child process, then runs the Async server
    # in the main process. Blocks until the server exits or the window closes.
    #
    # @param output [IO] where to print the launch banner (default: +$stdout+)
    def run(output: $stdout)
      output.puts "launching http://#{@host}:#{@port}"
      load_config

      browser_pid = fork_process { run_browser }
      browser_watchdog = start_browser_watchdog(browser_pid)

      run_server
    rescue Interrupt
      nil
    ensure
      if browser_pid
        browser_watchdog&.kill
        terminate_process(browser_pid)
      end
    end

    private

    # Runs the server in the main process.
    def run_server
      require "console"
      require "duoruby/server"
      Console.logger.fatal!
      Server.build(root: @root, host: @host, port: @port)
            .run(output: File.open(File::NULL, "w"))
    end

    # Runs the browser in the child process.
    def run_browser
      wait_for_server

      require "webview_util"

      title = @title || DuoRuby.config.title
      window = WebviewUtil::Window.new(title: title, width: @width, height: @height)
      window.navigate("http://#{@host}:#{@port}")
      window.run
    end

    def load_config
      config_path = File.join(@root, "duoruby.rb")
      load config_path if File.file?(config_path)
    end

    # Allocates a free TCP port by binding to port 0 and reading the assigned port.
    def free_port
      server = TCPServer.new(@host, 0)
      server.addr[1]
    ensure
      server&.close
    end

    # Polls until the server is accepting TCP connections.
    def wait_for_server
      loop do
        TCPSocket.new(@host, @port).close
        break
      rescue Errno::ECONNREFUSED
        sleep 0.05
      end
    end

    def fork_process(&block) = fork(&block)

    def start_browser_watchdog(browser_pid)
      Thread.new do
        wait_process(browser_pid)
        interrupt_server
      rescue Errno::ECHILD
        nil
      end
    end

    def terminate_process(pid)
      Process.kill(:TERM, pid) rescue nil
      wait_process(pid) rescue nil
    end

    def wait_process(pid) = Process.waitpid(pid)

    def interrupt_server = Thread.main.raise(Interrupt)
  end
end
