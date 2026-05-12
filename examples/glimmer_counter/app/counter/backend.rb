# frozen_string_literal: true

require "duoruby/backend"

module Counter
  class Backend < DuoRuby::Backend
    on :$connect do |client|
      client.send :count, value: @count
    end

    on :increment do |client|
      @count += 1
      group(:all).send :count, value: @count
    end

    on :decrement do |client|
      @count -= 1
      group(:all).send :count, value: @count
    end

    on :reset do |client|
      @count = 0
      group(:all).send :count, value: @count
    end

    def initialize
      super
      @count = 0
    end

    def connect(id:, writer: nil, &writer_block)
      client = super
      group(:all) << client
      client
    end
  end
end
