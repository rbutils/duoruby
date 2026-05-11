# frozen_string_literal: true

require "duoruby/backend"
require "duoruby/boot"

module DuoRuby
  # Creates a new {Backend} instance, optionally configuring it via a block.
  #
  # The block is evaluated in the context of the backend instance, so handler
  # registration methods (+on+, +one+, +off+) are available directly.
  #
  # @example
  #   backend = DuoRuby.backend do
  #     on(:join) { |client, room:| group(room) << client }
  #   end
  #
  # @yieldparam — (block is instance_eval'd on the backend; no explicit param)
  # @return [Backend]
  def self.backend(&block)
    Backend.new.tap do |backend|
      backend.instance_eval(&block) if block
    end
  end
end
