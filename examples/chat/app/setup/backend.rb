# frozen_string_literal: true

require "duoruby/setup/backend"
require "chat/backend"

DuoRuby.app = Chat::Backend.new
