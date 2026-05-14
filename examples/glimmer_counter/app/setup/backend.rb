# frozen_string_literal: true

require "duoruby/setup/backend"
require "counter/server"

DuoRuby.app = Counter::Server.new
