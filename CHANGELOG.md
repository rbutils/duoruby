# Changelog

## v0.1.1 - 2026-05-17

- Moved native launch ownership onto `DuoRuby::Server#launch`; `duoruby launch` now builds the application server and launches that instance.
- Removed the separate `DuoRuby::Launcher` API.
- Reversed launch process ownership so the main process runs the server and the forked child owns the native webview.
- Added block-style channel namespaces for `on` and `send`, including both `channel(:name) { ... }` and yielded `channel(:name) { |namespace| ... }` forms.
- Stopped tracking `Gemfile.lock` files in the gem and examples.

## v0.1.0 - 2026-05-17

- Initial prerelease.
