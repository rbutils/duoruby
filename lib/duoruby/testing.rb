# frozen_string_literal: true

require "duoruby/setup/backend"
require "duoruby/setup/frontend"

module DuoRuby
  module Testing
    Connection = Struct.new(:backend, :frontend, :client, keyword_init: true)

    def self.connect(backend: Backend.new, frontend: Frontend.new, id: "client-1", metadata: {})
      frontend = frontend.class.new if frontend.is_a?(Class)
      client = nil
      frontend_transport = proc { |message| backend.receive(client, message) }

      frontend.transport = frontend_transport
      client = backend.connect(id: id, metadata: metadata) { |message| frontend.receive(message) }
      Connection.new(backend: backend, frontend: frontend, client: client)
    end
  end
end
