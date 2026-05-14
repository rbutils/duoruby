# frozen_string_literal: true

require "duoruby/setup/backend"
require "duoruby/setup/frontend"

module DuoRuby
  module Testing
    Connection = Struct.new(:backend, :socket, :client, keyword_init: true)

    def self.connect(backend: Backend.new, socket: Socket.new, id: "client-1", metadata: {})
      socket = socket.class.new if socket.is_a?(Class)
      client = nil
      socket_transport = proc { |message| backend.receive(client, message) }

      socket.transport = socket_transport
      client = backend.connect(id: id, metadata: metadata) { |message| socket.receive(message) }
      Connection.new(backend: backend, socket: socket, client: client)
    end
  end
end
