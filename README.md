# DuoRuby

DuoRuby is a lightweight Ruby framework for WebSocket-first applications with a CRuby server and an Opal browser socket.

It gives Ruby applications a compact message DSL that works on both sides of the connection: browser sockets, server-side clients, and groups all use `send :event, **params`, while handlers use `on :event` with keyword parameters.

The main use case is building web-based desktop applications: run Ruby on the local machine, write the frontend in Ruby through Opal, open it with `duoruby launch`, and still keep the same app loadable remotely through `duoruby serve`.

The API and CLI are still evolving and should be considered unstable until version 1.0.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "duoruby"
```

And then execute:

```sh
bundle install
```

For local development from this checkout:

```sh
bundle install
bundle exec rake
bundle exec rake opal_spec
```

## How It Works

DuoRuby is organized around one server object and one browser socket object:

- `DuoRuby::Server` owns HTTP serving, WebSocket upgrades, connected clients, groups, authentication hooks, and message handlers.
- `DuoRuby::Socket` runs in the browser through Opal and owns the client-side WebSocket transport.
- `require "duoruby"` loads the server setup on CRuby and the browser setup on Opal.
- Application boot files live at `app/setup/backend.rb` and `app/setup/frontend.rb`.
- `duoruby serve` starts the Falcon-backed development server, serves `/`, compiles Opal frontend code to `/duoruby/app.js`, and bridges `/duoruby/socket` to the server.
- `duoruby launch` starts the same server and opens it in a native webview window for a desktop-app feel.
- Because launched apps are still served over HTTP/WebSocket, the same project can also be loaded from another browser when you expose the host/port intentionally.

Rack is not part of the default boot path.

## Quick Start

Server-side application code:

```ruby
class Chat::Server < DuoRuby::Server
  on :join do |client, name:|
    client[:name] = name
    group(:lobby) << client
    group(:lobby).send(:joined, name: name)
  end

  on :message do |client, text:|
    group(:lobby).send(:message, name: client[:name], text: text)
  end

  on :name? do |client|
    client[:name]
  end
end
```

Browser-side application code:

```ruby
class Chat::Socket < DuoRuby::Socket
  on :joined do |name:|
    puts "#{name} joined"
  end

  on :message do |name:, text:|
    puts "#{name}: #{text}"
  end
end

socket = Chat::Socket.new
socket.connect
socket.send(:join, name: "Ada")
```

Events ending in `?` are request/reply questions. They return a promise that can be awaited:

```ruby
# await: true

name = socket.send(:name?).__await__
```

Handlers reply to questions by returning a value. If a handler raises, DuoRuby sends a structured error reply.

## Examples

Run the chat example:

```sh
cd examples/chat
bundle install
bundle exec duoruby serve
```

Open `http://127.0.0.1:9292` in two browser windows. The sample app supports named rooms, presence lists, recent room history, room switching, leave, and validation errors.

To open it in a native webview window instead:

```sh
bundle exec duoruby launch
```

Run the Glimmer counter example:

```sh
cd examples/glimmer_counter
bundle install
bundle exec duoruby serve
```

Run the Ready Room game example:

```sh
cd examples/ready_room
bundle install
bundle exec duoruby serve
```

Ready Room demonstrates namespaced game events, browser-to-server questions, server-to-browser questions, group question collections, structured reply errors, and reconnect state sync.

## API

- `DuoRuby::Server#on(event, &block)` registers server-side message handlers.
- `DuoRuby::Server#group(name)` returns a broadcast group.
- `DuoRuby::Server#broadcast(event, **params)` sends an event to all connected clients.
- `DuoRuby::Client#channel(name)` and `DuoRuby::Group#channel(name)` send namespaced events without spelling raw colon-prefixed event names.
- `DuoRuby::Socket#connect` opens the default `/duoruby/socket` transport.
- `DuoRuby::Socket#send(event, **params)` sends fire-and-forget events or promise-returning `?` questions.
- `DuoRuby::Client#send(event, **params)` sends from the server to a browser socket with the same `?` question convention.
- `DuoRuby::Testing.connect` wires a server and socket together in memory for specs.
- `duoruby launch [--host HOST] [--port PORT] [--title TITLE]` runs the app server and opens a native webview window.

Lifecycle events use `$`-prefixed names:

- `:$connect`
- `:$disconnect`
- `:$reconnect`

## Development

Run from the repository root:

```sh
bundle install
bundle exec rake
bundle exec rake opal_spec
```

The default Rake task runs the CRuby RSpec suite. `bundle exec rake opal_spec` runs the Opal browser-side specs.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rbutils/duoruby.

## License

The gem is available as open source under the terms of the [MIT License](LICENSE.txt).
