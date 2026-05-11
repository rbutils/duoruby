# frozen_string_literal: true

module Chat
  class Log
    attr_reader :entries

    def initialize
      @entries = []
    end

    def joined(room:, name:)
      entries << "#{name} joined #{room}"
    end

    def left(room:, name:)
      entries << "#{name} left #{room}"
    end

    def message(name:, text:)
      entries << "#{name}: #{text}"
    end

    def system(text:)
      entries << text
    end

    def error(text:)
      entries << "Error: #{text}"
    end

    def replace(messages)
      entries.clear
      messages.each do |message|
        name = message.fetch("name")
        text = message.fetch("text")
        entries << (name == "system" ? text : "#{name}: #{text}")
      end
    end
  end
end
