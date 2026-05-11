# frozen_string_literal: true

require "chat/log"
require "duoruby/frontend"

module Chat
  class Frontend < DuoRuby::Frontend
    attr_reader :log, :messages, :rooms, :users, :status
    attr_accessor :room, :name

    on(:$connect) do
      set_status("Connected")
    end

    on(:$disconnect) do
      set_status("Disconnected")
    end

    on(:snapshot) do |room:, name:, rooms:, users:, history:|
      self.room = room
      self.name = name
      replace_list(self.rooms, rooms)
      replace_list(self.users, users)
      log.replace(history)
      render_messages
      set_status("Joined #{room} as #{name}")
    end

    on(:joined) do |room:, name:|
      log.joined(room: room, name: name)
      append("#{name} joined #{room}")
    end

    on(:left) do |room:, name:|
      log.left(room: room, name: name)
      append("#{name} left #{room}")
      set_status("Left #{room}")
    end

    on(:message) do |name:, text:, **|
      log.message(name: name, text: text)
      append("#{name}: #{text}")
    end

    on(:system) do |text:, **|
      log.system(text: text)
      append(text)
    end

    on(:presence) do |users:, **|
      replace_list(self.users, users)
    end

    on(:error) do |text:|
      log.error(text: text)
      append("Error: #{text}")
      set_status(text)
    end

    def initialize(transport: nil, log: Log.new, messages: nil, rooms: nil, users: nil, status: nil, &transport_block)
      super(transport: transport, &transport_block)
      @log = log
      @messages = messages
      @rooms = rooms
      @users = users
      @status = status
      @room = Chat.default_room
      @name = "anonymous"
    end

    def append(entry)
      return unless messages

      item = messages.document.create_element("li")
      item.text = entry
      messages << item
    end

    def render_messages
      return unless messages

      messages.clear
      log.entries.each { |entry| append(entry) }
    end

    def replace_list(list, values)
      return unless list

      list.clear
      values.each do |value|
        item = list.document.create_element("li")
        item.text = value
        list << item
      end
    end

    def set_status(text)
      status.text = text if status
    end
  end
end
