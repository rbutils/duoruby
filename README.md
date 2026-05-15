# DuoRuby

DuoRuby is a lightweight Ruby framework for WebSocket-first applications with a CRuby server and an Opal browser socket.

It gives Ruby applications a compact message DSL that works on both sides of the connection: browser sockets, server-side clients, and groups all use `send :event, **params`, while handlers use `on :event` with keyword parameters.

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
bundle exec ../../exe/duoruby serve
```

Open `http://127.0.0.1:9292` in two browser windows. The sample app supports named rooms, presence lists, recent room history, room switching, leave, and validation errors.

Run the Glimmer counter example:

```sh
cd examples/glimmer_counter
bundle exec ../../exe/duoruby serve
```

## API

- `DuoRuby::Server#on(event, &block)` registers server-side message handlers.
- `DuoRuby::Server#group(name)` returns a broadcast group.
- `DuoRuby::Server#broadcast(event, **params)` sends an event to all connected clients.
- `DuoRuby::Socket#connect` opens the default `/duoruby/socket` transport.
- `DuoRuby::Socket#send(event, **params)` sends fire-and-forget events or promise-returning `?` questions.
- `DuoRuby::Client#send(event, **params)` sends from the server to a browser socket with the same `?` question convention.
- `DuoRuby::Testing.connect` wires a server and socket together in memory for specs.

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
