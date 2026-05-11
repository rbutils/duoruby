# frozen_string_literal: true

require "json"
require "opal"
require "opal/builder"
require "opal-browser"
require "async"
require "async/http/endpoint"
require "async/websocket/adapters/http"
require "falcon/server"
require "protocol/http/response"
require "duoruby/backend/setup"

module DuoRuby
  # HTTP and WebSocket server built on Falcon and Async.
  #
  # Server handles three routes:
  # - +GET /+               — serves an HTML shell page that loads the frontend script
  # - +GET /duoruby/app.js+ — compiles and serves the Opal frontend on demand
  # - +GET /duoruby/socket+ — upgrades to a WebSocket and drives the backend
  #
  # The backend is loaded via {DuoRuby.load_app} unless one is supplied explicitly.
  # Every WebSocket connection creates a {Client}, routes inbound JSON frames through
  # {Backend#receive}, and cleans up via {Backend#disconnect} on close.
  #
  # @example Starting the server from application code
  #   DuoRuby::Server.new(root: __dir__, port: 3000).run
  class Server
    # Path that the browser WebSocket connects to.
    SOCKET_PATH = "/duoruby/socket"

    # Path from which the compiled frontend JavaScript is served.
    SCRIPT_PATH = "/duoruby/app.js"

    # @return [String] the expanded application root directory
    attr_reader :root

    # @return [String] the bind host
    attr_reader :host

    # @return [Integer] the bind port
    attr_reader :port

    # @return [Backend] the backend instance used for this server
    attr_reader :backend

    # @param root [String] the application root directory
    # @param host [String] the hostname or IP to bind to (default: +"127.0.0.1"+)
    # @param port [Integer, String] the port to listen on (default: +9292+)
    # @param backend [Backend, nil] an explicit backend instance; if omitted,
    #   the backend is loaded from +<root>/app/backend/setup.rb+ via {DuoRuby.load_app}
    def initialize(root: Dir.pwd, host: "127.0.0.1", port: 9292, backend: nil)
      @root = File.expand_path(root)
      @host = host
      @port = Integer(port)
      @backend = backend || DuoRuby.load_app(:backend, root: @root)
      @next_client_id = 0
    end

    # Rack-compatible request handler. Routes to the appropriate private handler
    # or returns a 404. Catches +StandardError+ and responds with a 500.
    #
    # @param request [Protocol::HTTP::Request]
    # @return [Protocol::HTTP::Response]
    def call(request)
      path = request.path.to_s.split("?", 2).first

      case path
      when SOCKET_PATH
        websocket(request) || not_found("websocket endpoint")
      when SCRIPT_PATH
        javascript
      when "/", ""
        html
      else
        not_found(path)
      end
    rescue StandardError => error
      text(500, "#{error.class}: #{error.message}\n")
    end

    # Starts the Falcon server and blocks until it exits.
    #
    # @param output [IO] where to print the "serving …" banner (default: +$stdout+)
    def run(output: $stdout)
      endpoint = Async::HTTP::Endpoint.parse("http://#{host}:#{port}")

      Sync do
        task = Falcon::Server.new(self, endpoint).run
        output.puts "serving http://#{host}:#{port}"
        task.wait
      ensure
        task&.stop
      end
    end

    # Compiles the Opal frontend to a JavaScript string.
    #
    # Resets Opal's global path state, adds the +opal-browser+ and +paggio+
    # gems, then builds the +opal+ runtime followed by +frontend/setup+
    # (which pulls in the application's +app/frontend/setup.rb+).
    #
    # Note: this method mutates global Opal state (+Opal.reset_paths!+) and
    # is not safe to call concurrently.
    #
    # @return [String] the concatenated JavaScript
    def frontend_javascript
      Opal.reset_paths!
      Opal.use_gem("opal-browser")
      Opal.use_gem("paggio")
      Opal.append_path(File.join(Gem::Specification.find_by_name("opal-browser").gem_dir, "opal"))

      builder = Opal::Builder.new
      builder.append_paths(File.join(root, "app"), File.expand_path("..", __dir__))
      builder.build("opal")
      builder.build("frontend/setup")
      builder.to_s
    end

    private

    # Upgrades the request to a WebSocket, creates a Client, and loops over
    # inbound frames until the connection closes.
    def websocket(request)
      Async::WebSocket::Adapters::HTTP.open(request) do |connection|
        client = backend.connect(id: next_client_id) do |message|
          connection.send_text(JSON.generate(message))
          connection.flush
        end

        while (text = connection.read)
          backend.receive(client, JSON.parse(text))
        end
      ensure
        backend.disconnect(client) if client
      end
    end

    # Returns a new sequential client ID string.
    def next_client_id
      @next_client_id += 1
      "client-#{@next_client_id}"
    end

    # Returns the HTML shell response.
    def html
      body = <<~HTML
        <!doctype html>
        <html>
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>DuoRuby</title>
          </head>
          <body>
            <div id="duoruby-root"></div>
            <script src="#{SCRIPT_PATH}?#{Time.now.to_i}"></script>
          </body>
        </html>
      HTML

      response(200, body, "text/html")
    end

    # Returns the compiled JavaScript response.
    def javascript
      response(200, frontend_javascript, "application/javascript")
    end

    # Returns a plain-text 404 response.
    def not_found(path)
      text(404, "not found: #{path}\n")
    end

    # Returns a plain-text response with the given status code.
    def text(status, body)
      response(status, body, "text/plain")
    end

    # Constructs a Protocol::HTTP::Response.
    def response(status, body, content_type)
      Protocol::HTTP::Response[status, {"content-type" => content_type}, [body]]
    end
  end
end
