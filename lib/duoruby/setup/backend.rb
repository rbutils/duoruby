# frozen_string_literal: true

require "duoruby/server"
require "duoruby/boot"

module DuoRuby
  # Creates a new application {Server} instance, optionally configuring it via a block.
  #
  # The block is evaluated in the context of the server instance, so handler
  # registration methods (+on+, +one+, +off+) are available directly.
  #
  # @example
  #   server = DuoRuby.server do
  #     on(:join) { |client, room:| group(room) << client }
  #   end
  #
  # @yieldparam — (block is instance_eval'd on the server; no explicit param)
  # @return [Server]
  def self.server(&block)
    Server.new.tap do |server|
      server.instance_eval(&block) if block
    end
  end
end
