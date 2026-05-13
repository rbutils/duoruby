# DuoRuby

DuoRuby is a lightweight Ruby framework experiment for WebSocket-first apps with a CRuby backend and an Opal frontend.

The initial shape is intentionally small:

- `require "duoruby"` loads backend setup on CRuby and frontend setup on Opal.
- Code is common by default unless its file name says `frontend` or `backend`.
- Application boot files are `app/setup/backend.rb` and `app/setup/frontend.rb`; see `examples/chat` for the sample app.
- Frontend, backend clients, and groups use the same message API: `send :event, **params`; handlers use `on :event` with keyword params.
- Browser frontends can call `connect` to use the default `/duoruby/socket` transport; socket open/close arrive as `on :$connect` and `on :$disconnect` handlers.
- `duoruby serve` starts the Falcon-backed development server, serves `/`, compiles frontend Opal to `/duoruby/app.js`, and bridges `/duoruby/socket` to the backend.
- Rack is not part of the default boot path.

## Chat Example

```sh
cd examples/chat
bundle exec ../../exe/duoruby serve
```

Open `http://127.0.0.1:9292` in two browser windows. The sample app supports named rooms, presence lists, recent room history, room switching, leave, and validation errors.

## Development

```sh
bundle install
bundle exec rspec
bundle exec opal-rspec -Ilib -Ispec/opal --default-path spec/opal spec/opal
```
