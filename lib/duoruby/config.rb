# frozen_string_literal: true

module DuoRuby
  # Holds framework-level configuration set by the application's +duoruby.rb+.
  #
  # @example In <root>/duoruby.rb
  #   DuoRuby.configure do |c|
  #     c.title = "My App"
  #   end
  class Config
    # @return [String] the window title used by +duoruby launch+
    attr_accessor :title

    # @return [String, nil] the server host, set by the framework before loading the app
    attr_accessor :host

    # @return [Integer, nil] the server port, set by the framework before loading the app
    attr_accessor :port

    def initialize
      @title = "DuoRuby"
    end
  end

  # Returns the current framework configuration object.
  # @return [Config]
  def self.config
    @config ||= Config.new
  end

  # Yields the configuration object for mutation.
  #
  # @yieldparam config [Config]
  def self.configure
    yield config
  end
end
