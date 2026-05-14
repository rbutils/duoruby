# frozen_string_literal: true

require "socket"
require "duoruby/config"
require "webview_util"

module DuoRuby
  # Starts the server in a child process and opens a native webview window
  # on the main process's main thread.
  #
  # GTK requires all calls on the thread that called gtk_init (the OS main
  # thread). The Async/Falcon server runs in a forked child process so each
  # has full ownership of its own event loop. When the window is closed the
  # child is terminated; when the child dies unexpectedly the window closes.
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

    # Forks the Async server into a child process, then opens the native
    # window on the main thread. Blocks until the window is closed, then
    # terminates the server child.
    #
    # @param output [IO] where to print the launch banner (default: +$stdout+)
    def run(output: $stdout)
      output.puts "launching http://#{@host}:#{@port}"

      server_pid = fork { run_server }

      wait_for_server

      title = @title || DuoRuby.config.title
      window = WebviewUtil::Window.new(title: title, width: @width, height: @height)
      window.navigate("http://#{@host}:#{@port}")
      window.run
    ensure
      if server_pid
        Process.kill(:TERM, server_pid) rescue nil
        Process.waitpid(server_pid) rescue nil
      end
    end

    private

    # Runs the server in the child process.
    def run_server
      require "console"
      require "duoruby/server"
      Console.logger.fatal!
      Server.build(root: @root, host: @host, port: @port)
            .run(output: File.open(File::NULL, "w"))
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
  end
end
