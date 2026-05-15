# frozen_string_literal: true

require "json"
require "uri"
require "async"
require "async/http/endpoint"
require "async/websocket/adapters/http"
require "falcon/server"
require "protocol/http/response"
require "duoruby/boot"
require "duoruby/message"
require "duoruby/channel"
require "duoruby/client"
require "duoruby/group"

module DuoRuby
  # Application server built on Falcon and Async.
  #
  # Server handles three HTTP routes:
  # - +GET /+               — serves an HTML shell page that loads the frontend script
  # - +GET /duoruby/app.js+ — compiles and serves the Opal frontend on demand
  # - +GET /duoruby/socket+ — upgrades to a WebSocket and drives message handlers
  #
  # Subclasses can declare message handlers with +on+ and can override +#call+ for
  # custom HTTP routes before delegating to +super+.
  #
  # @example Starting the server from application code
  #   DuoRuby::Server.build(root: __dir__, port: 3000).run
  class Server < Channel
    require "duoruby/server/frontend_compiler"

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

    # @return [Hash{Symbol => Group}] all groups that have been accessed on this server
    attr_reader :groups

    # @param root [String] the application root directory
    # @param host [String] the hostname or IP to bind to (default: +"127.0.0.1"+)
    # @param port [Integer, String] the port to listen on (default: +9292+)
    def initialize(root: Dir.pwd, host: "127.0.0.1", port: 9292)
      super()
      configure(root: root, host: host, port: port)
      @groups = {}
      @next_client_id = 0
    end

    def self.build(root: Dir.pwd, host: "127.0.0.1", port: 9292)
      root = File.expand_path(root)
      server = DuoRuby.load_app(:backend, root: root) || new(root: root, host: host, port: port)
      server.configure(root: root, host: host, port: port)
      server
    end

    def configure(root:, host:, port:)
      @root = File.expand_path(root)
      config_path = File.join(@root, "duoruby.rb")
      load config_path if File.file?(config_path)
      @host = host
      @port = Integer(port)
      DuoRuby.config.host = @host
      DuoRuby.config.port = @port
      self
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
    # Resets Opal's global path state, adds configured frontend gems, then
    # builds the +opal+ runtime followed by +setup/frontend+.
    #
    # Note: this method mutates global Opal state (+Opal.reset_paths!+) and
    # is not safe to call concurrently.
    #
    # @return [String] the concatenated JavaScript
    def frontend_javascript
      FrontendCompiler.new(root).call
    end

    def connect(id:, writer: nil, metadata: {}, &writer_block)
      client = Client.new(id: id, writer: writer, metadata: metadata, &writer_block)
      return client.reject unless authenticate(client)

      dispatch(:$connect, client)
      client
    end

    def authenticate(_client)
      true
    end

    def disconnect(client)
      dispatch(:$disconnect, client)
      client.cancel_pending_calls
      client.groups.values.each { |group| group.remove(client) }
      client
    end

    def group(name)
      groups[name.to_sym] ||= Group.new(name)
    end

    def broadcast(group_name, event, **params)
      group(group_name).send(event, **params)
    end

    def receive(client, message)
      message = Message.coerce(message)
      return client.resolve_call(message) if message.event == Message::REPLY_EVENT
      return client.reject_call(message) if message.event == Message::ERROR_EVENT && message.reply_to

      results = dispatch(message.event, client, **message.params)
      client.deliver(Message.reply(message.id, results.last)) if message.id
      results
    rescue StandardError => error
      raise unless message&.id

      client.deliver(Message.error(code: error.class.name, message: error.message, reply_to: message.id))
    end

    private

    # Upgrades the request to a WebSocket, creates a Client, and loops over
    # inbound frames until the connection closes.
    def websocket(request)
      Async::WebSocket::Adapters::HTTP.open(request) do |connection|
        client = connect(id: next_client_id, metadata: connection_metadata(request)) do |message|
          connection.send_text(JSON.generate(message))
          connection.flush
        end
        return unless client.accepted?

        while (text = connection.read)
          receive(client, JSON.parse(text))
        end
      ensure
        disconnect(client) if client
      end
    end

    # Returns a new sequential client ID string.
    def next_client_id
      @next_client_id += 1
      "client-#{@next_client_id}"
    end

    def connection_metadata(request)
      query = request.path.to_s.split("?", 2)[1]
      {
        path: request.path.to_s.split("?", 2).first,
        query: query ? URI.decode_www_form(query).to_h : {},
        headers: request.headers.each.to_h
      }
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
      js = Thread.new { frontend_javascript }.value
      response(200, js, "application/javascript")
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
