# frozen_string_literal: true

require "duoruby/setup/frontend"
require "counter/frontend"

Document.ready? do
  Counter::Frontend.new.start
end
