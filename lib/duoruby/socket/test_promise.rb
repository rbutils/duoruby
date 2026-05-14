# frozen_string_literal: true

module DuoRuby
  class Socket
    class TestPromise
      attr_reader :value, :error

      def initialize
        @resolved = false
        @rejected = false
        @then_handlers = []
        @fail_handlers = []
      end

      def resolve(value = nil)
        @resolved = true
        @value = value
        @then_handlers.each { |handler| handler.call(value) }
        self
      end

      def reject(error = nil)
        @rejected = true
        @error = error
        @fail_handlers.each { |handler| handler.call(error) }
        self
      end

      def then(&handler)
        @resolved ? handler.call(value) : @then_handlers << handler
        self
      end

      def fail(&handler)
        @rejected ? handler.call(error) : @fail_handlers << handler
        self
      end

      alias_method :rescue, :fail
    end
  end
end
