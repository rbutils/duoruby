# frozen_string_literal: true

require "duoruby/setup/backend"
require "counter/backend"

DuoRuby.app = Counter::Backend.new
