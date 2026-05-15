# frozen_string_literal: true

require "ready_room"
require "duoruby/server"

module ReadyRoom
  class Server < DuoRuby::Server
    attr_reader :players, :answers, :votes

    on(:$connect) do |client|
      client[:room] = ReadyRoom.default_room
    end

    on(:$disconnect) do |client|
      leave_player(client)
    end

    channel(:game).on(:join?) do |client, name:|
      name = normalize_name(name)
      raise ArgumentError, "name is already taken" if players.key?(name) && players[name] != client

      leave_player(client) if client[:name] && client[:name] != name
      client[:name] = name
      client[:ready] = false
      players[name] = client
      group(:players) << client
      broadcast_state("#{name} joined")
      state_for(client)
    end

    channel(:game).on(:ready) do |client, ready: true|
      require_player(client)
      client[:ready] = !!ready
      broadcast_state("#{client[:name]} is #{client[:ready] ? "ready" : "not ready"}")
    end

    channel(:game).on(:answer) do |client, text:|
      require_player(client)
      text = normalize_text(text)
      raise ArgumentError, "answer cannot be blank" if text.empty?

      answers[client[:name]] = text
      broadcast_state("#{client[:name]} answered")
    end

    channel(:game).on(:state?) do |client|
      state_for(client)
    end

    channel(:game).on(:start_round?) do |client|
      require_player(client)
      statuses = ask_ready_players
      waiting = statuses.select { |status| !status.fetch("ready") }.map { |status| status.fetch("name") }
      raise ArgumentError, "waiting for #{waiting.join(", ")}" unless waiting.empty?

      @answers = {}
      @votes = {}
      group(:players).channel(:game).send(:round_started, prompt: ReadyRoom.prompt)
      state_for(client)
    end

    channel(:game).on(:score?) do |client|
      require_player(client)
      raise ArgumentError, "no answers yet" if answers.empty?

      choices = answers.map { |name, text| {"name" => name, "text" => text} }
      replies = group(:players).channel(:game).send(:vote?, choices: choices)
      @votes = tally_votes(replies.map(&:await))
      broadcast_state("votes collected")
      scoreboard
    end

    def initialize
      super
      @players = {}
      @answers = {}
      @votes = {}
    end

    def ask_ready_players = group(:players).channel(:game).send(:ready?).map(&:await)

    def scoreboard
      answers.map do |name, text|
        {"name" => name, "text" => text, "votes" => votes.fetch(name, 0)}
      end.sort_by { |entry| [-entry.fetch("votes"), entry.fetch("name")] }
    end

    private

    def leave_player(client)
      name = client[:name]
      return unless name

      players.delete(name)
      group(:players).remove(client)
      client[:name] = nil
      client[:ready] = false
      answers.delete(name)
      votes.delete(name)
      broadcast_state("#{name} left") unless group(:players).empty?
    end

    def broadcast_state(message) = group(:players).channel(:game).send(:state, state: state, message: message)

    def state_for(client) = state.merge("you" => client[:name])

    def state
      {
        "prompt" => ReadyRoom.prompt,
        "players" => players.keys,
        "ready" => players.transform_values { |client| !!client[:ready] },
        "answers" => answers.dup,
        "scoreboard" => scoreboard
      }
    end

    def tally_votes(replies)
      replies.each_with_object(Hash.new(0)) do |reply, tally|
        name = reply.fetch("vote").to_s
        tally[name] += 1 if answers.key?(name)
      end
    end

    def require_player(client)
      raise ArgumentError, "join before playing" unless client[:name]
    end

    def normalize_name(name)
      value = name.to_s.strip
      raise ArgumentError, "name cannot be blank" if value.empty?

      value[0, 24]
    end

    def normalize_text(text) = text.to_s.strip[0, 160]
  end
end
