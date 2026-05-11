# frozen_string_literal: true

require "socket"
require "duoruby/server"
require "duoruby/config"
require "webview_util"

module DuoRuby
  # Starts the server on a free port and opens a native webview window.
  #
  # The server runs in a background thread; the webview window blocks the
  # calling thread until the user closes it, at which point the server is
  # stopped.
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

    # Starts the server in a background thread, opens the native window, and
    # blocks until the window is closed. Stops the server on exit.
    #
    # @param output [IO] where to print the launch banner (default: +$stdout+)
    def run(output: $stdout)
      server = Server.new(root: @root, host: @host, port: @port)
      server_thread = start_server(server)
      sleep 0.1 # give the server a moment to bind

      title = @title || DuoRuby.config.title
      output.puts "launching http://#{@host}:#{@port}"

      window = WebviewUtil::Window.new(title: title, width: @width, height: @height)
      window.navigate("http://#{@host}:#{@port}")
      window.run
    ensure
      server_thread&.kill
    end

    private

    # Allocates a free TCP port by binding to port 0 and reading the assigned port.
    def free_port
      server = TCPServer.new(@host, 0)
      server.addr[1]
    ensure
      server&.close
    end

    # Starts the server in a background thread.
    def start_server(server)
      Thread.new do
        server.run(output: File.open(File::NULL, "w"))
      rescue StandardError
        # thread exits cleanly when window closes and we kill it
      end
    end
  end
end
