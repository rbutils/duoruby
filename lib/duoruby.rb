# frozen_string_literal: true

# DuoRuby — a lightweight dual-runtime WebSocket framework.
#
# This top-level loader requires the protocol primitives ({DuoRuby::Message} and
# {DuoRuby::Channel}) that are shared between the server and frontend, then
# branches on the Ruby engine:
#
# - Under *CRuby* it loads {DuoRuby::Server} and the {DuoRuby.server} factory
#   (+duoruby/setup/backend+).
# - Under *Opal* it loads {DuoRuby::Socket}, the Opal/browser dependencies,
#   and the {DuoRuby.socket} factory (+duoruby/setup/frontend+).
#
# Application entry points (+app/setup/backend.rb+ and +app/setup/frontend.rb+)
# are loaded separately by {DuoRuby.boot} or {DuoRuby.load_app}.

require "duoruby/message"
require "duoruby/channel"

if RUBY_ENGINE == "opal"
  require "duoruby/setup/frontend"
else
  require "duoruby/setup/backend"
end
