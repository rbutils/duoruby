# frozen_string_literal: true

require "browser"
require "ready_room"
require "ready_room/socket"

module ReadyRoom
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

    attr_reader :name_input, :answer_input, :status, :players, :scoreboard

    def build
      root = document["duoruby-ready-room"] || document["duoruby-root"] || document.body
      root.clear
      install_styles

      title = document.create_element("h1")
      title.text = "Ready Room"
      prompt = document.create_element("p")
      prompt.text = ReadyRoom.prompt
      @status = document.create_element("p", id: "status")
      status.text = "Connecting..."
      @players = document.create_element("ol", id: "players")
      @scoreboard = document.create_element("ol", id: "scoreboard")
      @name_input = input("name", "Name", "Ada")
      @answer_input = input("answer", "Answer")

      join_button = button("Join") { join }
      ready_button = button("Ready") { ready }
      start_button = button("Start") { start_round }
      answer_button = button("Answer") { answer }
      score_button = button("Score") { score }
      state_button = button("State?") { refresh_state }

      root << title << prompt << status << panel("Players", players) << panel("Scoreboard", scoreboard)
      root << name_input << answer_input << join_button << ready_button << start_button << answer_button << score_button << state_button
    end

    def connect
      @socket = Socket.new(name: name)
      socket.channel(:game).on(:state) { |state:, message: nil| render(state, message) }
      socket.connect(reconnect: true)
    end

    def join
      socket.name = name
      socket.join.then { |state| render(state, "joined") }.fail { |error| set_status(error.message) }
    end

    def ready = socket.mark_ready(true)

    def start_round
      socket.start_round.then { |state| render(state, "round started") }.fail { |error| set_status(error.message) }
    end

    def answer
      socket.answer(answer_input.value.to_s)
      answer_input.value = ""
    end

    def score
      socket.score.then { |entries| render_scoreboard(entries) }.fail { |error| set_status(error.message) }
    end

    def refresh_state = socket.state.then { |state| render(state, "state refreshed") }

    def render(state, message = nil)
      replace_list(players, state.fetch("players", []))
      render_scoreboard(state.fetch("scoreboard", []))
      set_status(message || "Ready")
    end

    def render_scoreboard(entries) = replace_list(scoreboard, entries.map { |entry| "#{entry.fetch("name")}: #{entry.fetch("votes")}" })

    def name
      value = name_input.value.to_s.strip
      value.empty? ? "anonymous" : value
    end

    def set_status(text) = status.text = text

    def input(id, placeholder, value = nil)
      element = document.create_element("input", id: id, attrs: {"placeholder" => placeholder})
      element.value = value if value
      element
    end

    def button(label, &block)
      element = document.create_element("button")
      element.text = label
      element.on(:click) { |event| event.prevent; block.call }
      element
    end

    def panel(title, list)
      element = document.create_element("section")
      heading = document.create_element("h2")
      heading.text = title
      element << heading << list
      element
    end

    def replace_list(list, values)
      list.clear
      values.each do |value|
        item = list.document.create_element("li")
        item.text = value
        list << item
      end
    end

    def install_styles
      style = document.create_element("style")
      style.text = <<~CSS
        body { margin: 0; font: 16px/1.4 system-ui, sans-serif; background: #201326; color: #fff7ed; }
        #duoruby-ready-room, #duoruby-root { max-width: 900px; margin: 0 auto; padding: 24px; }
        h1 { margin: 0; font-size: 40px; color: #fde68a; }
        #status { color: #c4b5fd; font-weight: 700; }
        section { display: inline-block; vertical-align: top; width: 42%; min-height: 120px; margin: 0 2% 18px 0; padding: 16px; background: #3b2148; border-radius: 16px; }
        input { box-sizing: border-box; width: 100%; margin: 0 0 10px; padding: 12px; border: 0; border-radius: 12px; }
        button { margin: 0 8px 8px 0; padding: 10px 14px; border: 0; border-radius: 999px; background: #f97316; color: white; font-weight: 800; }
      CSS
      document.head << style
    end
  end
end
