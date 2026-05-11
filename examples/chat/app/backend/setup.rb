# frozen_string_literal: true

require "duoruby/backend/setup"
require "chat/backend"

DuoRuby.app = Chat::Backend.new
