# frozen_string_literal: true

require "duoruby/version"

module DuoRuby
  # Command-line interface for the +duoruby+ executable.
  #
  # Commands:
  # - +help+    — prints usage information
  # - +version+ — prints the gem version
  # - +serve+   — starts the HTTP/WebSocket server (accepts +--host+ and +--port+ options)
  # - +launch+  — starts the server and opens a native webview window
  #
  # All commands return an integer exit code. +duoruby/server+ is required lazily
  # by +serve+ to avoid loading Falcon/Async for other commands.
  #
  # @example Programmatic use (mirrors the +exe/duoruby+ entry point)
  #   exit DuoRuby::CLI.new(ARGV, input: $stdin, output: $stdout).call
  class CLI
    # @param args [Array<String>] the command-line arguments (typically +ARGV+)
    # @param input [IO] standard input (reserved for future interactive use)
    # @param output [IO] standard output where all messages are printed
    def initialize(args, input:, output:)
      @args = args
      @input = input
      @output = output
    end

    # Dispatches to the appropriate command handler.
    #
    # @return [Integer] 0 on success, 1 on error
    def call
      case @args.first
      when nil, "help", "--help", "-h"
        help
      when "version", "--version", "-v"
        @output.puts VERSION
        0
      when "serve"
        serve
      when "launch"
        launch
      else
        @output.puts "unknown command: #{@args.first}"
        1
      end
    end

    private

    # Prints usage summary.
    # @return [Integer] 0
    def help
      @output.puts "duoruby help"
      @output.puts "duoruby version"
      @output.puts "duoruby serve [--host HOST] [--port PORT]"
      @output.puts "duoruby launch [--host HOST] [--port PORT] [--title TITLE]"
      0
    end

    # Parses +--host+ and +--port+ options, then starts the server.
    #
    # @return [Integer] 0 on success, 1 on option parse failure
    def serve
      options = serve_options
      return 1 unless options

      require "duoruby/server"

      DuoRuby::Server.new(**options).run(output: @output)
      0
    end

    # Parses options and opens a native webview window backed by the server.
    #
    # @return [Integer] 0 on success, 1 on option parse failure
    def launch
      options = launch_options
      return 1 unless options

      require "duoruby/launcher"

      DuoRuby::Launcher.new(**options).run(output: @output)
      0
    end

    # Parses the options that follow the +launch+ command.
    #
    # @return [Hash, nil]
    def launch_options
      options = {root: Dir.pwd}
      args = @args.drop(1)

      until args.empty?
        case (arg = args.shift)
        when "--host"
          return missing_option_value if args.empty?

          options[:host] = args.shift
        when "--port"
          return missing_option_value if args.empty?

          options[:port] = parse_port(args.shift)
          return unless options[:port]
        when "--title"
          return missing_option_value if args.empty?

          options[:title] = args.shift
        else
          @output.puts "unknown launch option: #{arg}"
          return
        end
      end

      options
    end

    # Parses the options that follow the +serve+ command.
    #
    # @return [Hash, nil] option hash on success, +nil+ on parse failure
    def serve_options
      options = {root: Dir.pwd}
      args = @args.drop(1)

      until args.empty?
        case (arg = args.shift)
        when "--host"
          return missing_option_value if args.empty?

          options[:host] = args.shift
        when "--port"
          return missing_option_value if args.empty?

          options[:port] = parse_port(args.shift)
          return unless options[:port]
        else
          @output.puts "unknown serve option: #{arg}"
          return
        end
      end

      options
    end

    # Prints a "missing value" error and returns +nil+.
    def missing_option_value
      @output.puts "missing option value"
      nil
    end

    # Parses +value+ as a TCP port number (1–65535).
    # Prints an error and returns +nil+ for anything invalid.
    #
    # @param value [String] the raw port string
    # @return [Integer, nil]
    def parse_port(value)
      port = Integer(value)
      return port if port.between?(1, 65_535)
    rescue ArgumentError, TypeError
      nil
    ensure
      @output.puts "invalid serve port: #{value}" unless port&.between?(1, 65_535)
    end
  end
end
