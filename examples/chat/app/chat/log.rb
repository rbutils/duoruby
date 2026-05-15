# frozen_string_literal: true

module Chat
  class Log
    attr_reader :entries

    def initialize = @entries = []

    def joined(room:, name:) = entries << "#{name} joined #{room}"

    def left(room:, name:) = entries << "#{name} left #{room}"

    def message(name:, text:) = entries << "#{name}: #{text}"

    def system(text:) = entries << text

    def error(text:) = entries << "Error: #{text}"

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
