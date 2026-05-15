# Ready Room

Ready Room is a small DuoRuby party-game example focused on request/reply events and namespace composition.

It demonstrates:

- browser-to-server questions with `socket.channel(:game).send(:state?)`
- server-to-browser questions with `client.channel(:game).send(:ready?).await`
- group question collections with `group(:players).channel(:game).send(:vote?)`
- structured reply errors for invalid joins and premature round starts
- reconnect state sync through `:$reconnect`
- ordinary group broadcasts for round and scoreboard updates

Run it from this directory:

```sh
bundle install
bundle exec duoruby serve
```

To open the app in a native webview window instead:

```sh
bundle exec duoruby launch
```
