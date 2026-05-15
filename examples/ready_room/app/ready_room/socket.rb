# frozen_string_literal: true

require "duoruby/socket"

module ReadyRoom
  class Socket < DuoRuby::Socket
    attr_reader :events, :states, :scoreboards, :errors
    attr_accessor :name, :ready, :vote

    on(:$connect) do
      events << "connected"
    end

    on(:$disconnect) do
      events << "disconnected"
    end

    on(:$reconnect) do
      events << "reconnected"
      channel(:game).send(:state?).then { |state| apply_state(state, "resynced") }
    end

    channel(:game).on(:state) do |state:, message: nil|
      apply_state(state, message)
    end

    channel(:game).on(:round_started) do |prompt:|
      events << "round: #{prompt}"
    end

    channel(:game).on(:ready?) do
      {"name" => name, "ready" => !!ready}
    end

    channel(:game).on(:vote?) do |choices:|
      selected = vote || choices.first.fetch("name")
      {"name" => name, "vote" => selected}
    end

    def initialize(name: "anonymous", ready: false, vote: nil, transport: nil, &transport_block)
      super(transport: transport, &transport_block)
      @name = name
      @ready = ready
      @vote = vote
      @events = []
      @states = []
      @scoreboards = []
      @errors = []
    end

    def join = channel(:game).send(:join?, name: name)

    def mark_ready(value = true)
      self.ready = value
      channel(:game).send(:ready, ready: value)
    end

    def answer(text) = channel(:game).send(:answer, text: text)

    def state = channel(:game).send(:state?)

    def start_round = channel(:game).send(:start_round?)

    def score = channel(:game).send(:score?)

    def apply_state(state, message = nil)
      states << state
      scoreboards << state.fetch("scoreboard", [])
      events << message if message
      state
    end
  end
end
