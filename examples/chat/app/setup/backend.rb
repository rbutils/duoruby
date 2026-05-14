# frozen_string_literal: true

require "duoruby/setup/backend"
require "chat/server"

DuoRuby.app = Chat::Server.new
