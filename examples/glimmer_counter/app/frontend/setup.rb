# frozen_string_literal: true

require "duoruby/frontend/setup"
require "counter/frontend"

Document.ready? do
  Counter::Frontend.new.start
end
