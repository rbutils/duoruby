# frozen_string_literal: true

require "duoruby/backend/setup"
require "counter/backend"

DuoRuby.app = Counter::Backend.new
