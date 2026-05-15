# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("lib", __dir__))
require "duoruby/version"

Gem::Specification.new do |spec|
  spec.name = "duoruby"
  spec.version = DuoRuby::VERSION
  spec.authors = ["DuoRuby contributors"]
  spec.email = ["duoruby@example.invalid"]

  spec.summary = "A lightweight Ruby framework for Opal-backed WebSocket apps."
  spec.description = "DuoRuby separates CRuby backend and Opal frontend setup while sharing protocol code."
  spec.homepage = "https://example.invalid/duoruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["allowed_push_host"] = "TODO: Set to your gem server or remove before release."
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*.rb", "exe/*", "README.md", "LICENSE.txt"]
  spec.bindir = "exe"
  spec.executables = ["duoruby"]
  spec.require_paths = ["lib"]

  spec.add_dependency "async", "~> 2.0"
  spec.add_dependency "async-websocket", "~> 0.30"
  spec.add_dependency "falcon", "~> 0.49"
  spec.add_dependency "opal", ">= 1.8"
  spec.add_dependency "opal-browser", ">= 0.3"
  spec.add_dependency "webview_util", ">= 0.1.0"
  spec.add_dependency "base64", ">= 0.2"

  spec.add_development_dependency "base64", ">= 0.2"
  spec.add_development_dependency "opal-rspec", ">= 1.1.0.alpha3"
  spec.add_development_dependency "rake", ">= 13.0"
  spec.add_development_dependency "rspec", ">= 3.13"
end
