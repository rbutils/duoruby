# frozen_string_literal: true

require "browser"
require "chat"
require "chat/socket"

module Chat
  class Browser
    attr_reader :document, :socket

    def initialize(document: $document)
      @document = document
    end

    def start
      document.ready do
        build
        connect
      end

      self
    end

    private

    attr_reader :name_input, :text_input, :room_input, :messages, :rooms, :users, :status

    def build
      root = document["duoruby-chat"] || document["duoruby-root"] || document.body
      root.clear
      install_styles

      title = document.create_element("h1")
      title.text = "DuoRuby team chat"

      @status = document.create_element("p", id: "status")
      status.text = "Connecting..."

      @messages = document.create_element("ol", id: "messages")
      @rooms = document.create_element("ol", id: "rooms")
      @users = document.create_element("ol", id: "users")
      @name_input = input("name", "Name")
      @room_input = input("room", "Room", Chat.default_room)
      @text_input = input("text", "Message")

      join_button = button("Join")
      send_button = button("Send")
      leave_button = button("Leave")

      join_button.on(:click) { |event| event.prevent; join }
      send_button.on(:click) { |event| event.prevent; speak }
      leave_button.on(:click) { |event| event.prevent; leave }
      text_input.on(:keypress) { |event| speak if enter?(event) }

      root << title << status << panel("Rooms", rooms) << panel("People", users) << messages
      root << name_input << room_input << text_input << join_button << send_button << leave_button
    end

    def connect
      @socket = Socket.new(messages: messages, rooms: rooms, users: users, status: status)
      socket.connect
    end

    def join
      socket.send(:join, room: room, name: name) if socket
    end

    def speak
      text = text_input.value.to_s
      return if text.empty?

      socket.send(:speak, room: room, text: text)
      text_input.value = ""
    end

    def leave
      socket.send(:leave) if socket
    end

    def room
      value = room_input.value.to_s
      value.empty? ? Chat.default_room : value
    end

    def name
      value = name_input.value.to_s
      value.empty? ? "anonymous" : value
    end

    def input(id, placeholder, value = nil)
      element = document.create_element("input", id: id, attrs: {"placeholder" => placeholder})
      element.value = value if value
      element
    end

    def button(label)
      element = document.create_element("button")
      element.text = label
      element
    end

    def panel(title, list)
      element = document.create_element("section")
      heading = document.create_element("h2")
      heading.text = title
      element << heading << list
      element
    end

    def enter?(event)
      event.key == "Enter"
    end

    def install_styles
      style = document.create_element("style")
      style.text = <<~CSS
        body { margin: 0; font: 16px/1.4 system-ui, sans-serif; background: #111827; color: #f9fafb; }
        #duoruby-chat, #duoruby-root { max-width: 960px; margin: 0 auto; padding: 24px; }
        h1 { margin: 0 0 8px; font-size: 32px; }
        h2 { margin: 0 0 8px; font-size: 16px; color: #93c5fd; }
        #status { color: #a7f3d0; }
        section { display: inline-block; vertical-align: top; width: 44%; min-height: 96px; margin: 0 2% 16px 0; padding: 16px; background: #1f2937; border-radius: 12px; }
        ol { margin: 0 0 16px; padding-left: 24px; }
        #messages { min-height: 260px; padding: 16px 16px 16px 40px; background: #030712; border-radius: 12px; }
        input { box-sizing: border-box; width: 100%; margin: 0 0 8px; padding: 12px; border: 1px solid #374151; border-radius: 10px; background: #f9fafb; color: #111827; }
        button { margin: 0 8px 8px 0; padding: 10px 16px; border: 0; border-radius: 999px; background: #2563eb; color: white; font-weight: 700; }
        button:last-child { background: #4b5563; }
      CSS
      document.head << style
    end

  end
end
