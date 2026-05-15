# frozen_string_literal: true

require "duoruby/setup/frontend"
require "ready_room/socket"
require "ready_room/browser"

ReadyRoom::Browser.new.start
