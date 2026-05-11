# frozen_string_literal: true

module Chat
  def self.rooms
    [default_room, "help", "random"]
  end

  def self.default_room
    "lobby"
  end

  def self.history_limit
    20
  end
end
