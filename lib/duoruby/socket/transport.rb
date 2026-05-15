# frozen_string_literal: true

module DuoRuby
  class Socket
    module Transport
      def self.included(receiver)
        receiver.extend(ClassMethods)
      end

      def connect(url: nil, path: "/duoruby/socket", reconnect: false, backoff: 1)
        raise "already connected" if @socket

        @connect_url = url || self.class.default_socket_url(path)
        @reconnect = reconnect
        @reconnect_backoff = backoff
        open_socket
        self
      end

      def reconnect
        @socket = nil
        open_socket
        trigger(:$reconnect)
        self
      end

      def open_socket
        @socket = self.class.socket_class.new(@connect_url)
        @transport = proc { |message| socket.write(JSON.generate(message)) }

        socket.on(:open) { trigger(:$connect) }
        socket.on(:message) { |event| receive(JSON.parse(event.data)) }
        socket.on(:close) do
          trigger(:$disconnect)
          cancel_pending_calls
          schedule_reconnect if @reconnect
        end
      end

      module ClassMethods
        def default_socket_url(path = "/duoruby/socket")
          raise "default socket transport is only available under Opal" unless RUBY_ENGINE == "opal"

          location = $window.location
          protocol = location.scheme == "https:" ? "wss:" : "ws:"
          "#{protocol}//#{location.host}#{path}"
        end

        def socket_class
          raise "default socket transport is only available under Opal" unless RUBY_ENGINE == "opal"

          ::Browser::Socket
        end
      end

      private

      def schedule_reconnect
        if RUBY_ENGINE == "opal"
          $window.set_timeout(proc { reconnect }, @reconnect_backoff * 1000)
        end
      end
    end
  end
end
