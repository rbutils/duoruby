# frozen_string_literal: true

require "duoruby/setup/backend"
require "ready_room/server"

DuoRuby.app = ReadyRoom::Server.new
