# frozen_string_literal: true

# DuoRuby — a lightweight dual-runtime WebSocket framework.
#
# This top-level loader requires the protocol primitives ({DuoRuby::Message} and
# {DuoRuby::Channel}) that are shared between the backend and frontend, then
# branches on the Ruby engine:
#
# - Under *CRuby* it loads {DuoRuby::Backend} and the {DuoRuby.backend} factory
#   (+duoruby/backend/setup+).
# - Under *Opal* it loads {DuoRuby::Frontend}, the Opal/browser dependencies,
#   and the {DuoRuby.frontend} factory (+duoruby/frontend/setup+).
#
# Application entry points (+app/backend/setup.rb+ and +app/frontend/setup.rb+)
# are loaded separately by {DuoRuby.boot} or {DuoRuby.load_app}.

require "duoruby/message"
require "duoruby/channel"

if RUBY_ENGINE == "opal"
  require "duoruby/frontend/setup"
else
  require "duoruby/backend/setup"
end
