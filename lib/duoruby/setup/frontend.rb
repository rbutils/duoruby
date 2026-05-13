# frozen_string_literal: true

require "duoruby/frontend"

# Load Opal/browser dependencies when running inside the compiled JavaScript bundle.
if RUBY_ENGINE == "opal"
  require "native"
  require "promise/v2"
  require "browser/setup/mini"
  require "browser/location"
  require "browser/socket"
end

module DuoRuby
  # Creates a new {Frontend} instance, optionally configuring it via a block.
  #
  # The block is evaluated in the context of the frontend instance, so handler
  # registration methods (+on+, +one+, +off+) are available directly.
  #
  # @example
  #   frontend = DuoRuby.frontend do
  #     on(:snapshot) { |rooms:, **| puts rooms.inspect }
  #   end
  #
  # @param transport [Proc, nil] optional transport callable (see {Frontend#initialize})
  # @yieldparam — (block is instance_eval'd on the frontend; no explicit param)
  # @return [Frontend]
  def self.frontend(transport: nil, &block)
    Frontend.new(transport: transport).tap do |frontend|
      frontend.instance_eval(&block) if block
    end
  end
end
