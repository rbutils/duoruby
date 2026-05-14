# frozen_string_literal: true

require "duoruby/setup/frontend"
require "chat/socket"
require "chat/browser"

Chat::Browser.new.start
