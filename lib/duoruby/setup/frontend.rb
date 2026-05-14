# frozen_string_literal: true

require "duoruby/socket"

# Load Opal/browser dependencies when running inside the compiled JavaScript bundle.
if RUBY_ENGINE == "opal"
  require "native"
  require "promise/v2"
  require "browser/setup/mini"
  require "browser/location"
  require "browser/socket"
end

module DuoRuby
  # Creates a new browser {Socket} instance, optionally configuring it via a block.
  #
  # The block is evaluated in the context of the socket instance, so handler
  # registration methods (+on+, +one+, +off+) are available directly.
  #
  # @example
  #   socket = DuoRuby.socket do
  #     on(:snapshot) { |rooms:, **| puts rooms.inspect }
  #   end
  #
  # @param transport [Proc, nil] optional transport callable (see {Socket#initialize})
  # @yieldparam — (block is instance_eval'd on the socket; no explicit param)
  # @return [Socket]
  def self.socket(transport: nil, &block)
    Socket.new(transport: transport).tap do |socket|
      socket.instance_eval(&block) if block
    end
  end
end
