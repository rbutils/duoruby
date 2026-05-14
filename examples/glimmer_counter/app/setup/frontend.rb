# frozen_string_literal: true

require "duoruby/setup/frontend"
require "counter/socket"

Document.ready? do
  Counter::Socket.new.start
end
