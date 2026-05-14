# frozen_string_literal: true

require "chat"
require "duoruby/server"

module Chat
  class Server < DuoRuby::Server
    attr_reader :room_members, :history

    on :$connect do |client|
      client[:connected] = true
    end

    on :$disconnect do |client|
      client[:connected] = false
      leave_room(client)
    end

    on :join do |client, room: Chat.default_room, name:|
      room = normalize_room(room)
      ensure_room(room)
      name = normalize_name(name)

      leave_room(client) if client[:room] && client[:room] != room

      client[:name] = name
      client[:room] = room
      room_members[room] << client unless room_members[room].include?(client)
      group(room) << client

      client.send :snapshot, room: room, name: name, rooms: rooms, users: users(room), history: history[room]
      group(room).send :presence, room: room, users: users(room)
      announce(room, "#{name} joined #{room}")
    end

    on :speak do |client, text:, **|
      return client.send(:error, text: "Join a room before sending messages") unless client[:room]

      room = normalize_room(client[:room])
      text = normalize_text(text)
      return client.send(:error, text: "Message cannot be blank") if text.empty?

      message = {"name" => client[:name], "text" => text}
      history[room] << message
      history[room].shift while history[room].length > Chat.history_limit
      group(room).send :message, room: room, name: client[:name], text: text
    end

    on :leave do |client|
      leave_room(client, notify_client: true)
    end

    def initialize
      super
      @room_members = {}
      @history = {}
      Chat.rooms.each do |room|
        @room_members[room] = []
        @history[room] = []
      end
    end

    def rooms
      (Chat.rooms + room_members.keys).uniq
    end

    def users(room)
      ensure_room(room)
      room_members[room].map { |client| client[:name] }
    end

    private

    def leave_room(client, notify_client: false)
      room = client[:room]
      return unless room

      ensure_room(room)
      name = client[:name]
      group(room).remove(client)
      room_members[room].delete(client)
      client[:room] = nil
      client.send(:left, room: room, name: name) if notify_client
      group(room).send :presence, room: room, users: users(room)
      announce(room, "#{name} left #{room}")
    end

    def announce(room, text)
      ensure_room(room)
      history[room] << {"name" => "system", "text" => text}
      history[room].shift while history[room].length > Chat.history_limit
      group(room).send :system, room: room, text: text
    end

    def ensure_room(room)
      room_members[room] ||= []
      history[room] ||= []
    end

    def normalize_name(name)
      value = name.to_s.strip
      value.empty? ? "anonymous" : value[0, 32]
    end

    def normalize_room(room)
      value = room.to_s.strip.downcase
      value = Chat.default_room if value.empty?
      value.gsub(/[^a-z0-9_-]/, "-")[0, 32]
    end

    def normalize_text(text)
      text.to_s.strip[0, 500]
    end
  end
end
