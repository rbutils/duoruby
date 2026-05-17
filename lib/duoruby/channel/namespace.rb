# frozen_string_literal: true

module DuoRuby
  class Channel
    class Namespace
      def self.call(target, name, &block)
        namespace = new(target, name)
        return namespace unless block
        return block.call(namespace) if block.arity.positive?

        namespace.instance_exec(&block)
      end

      def initialize(target, name)
        @target = target
        @name = name.to_s
      end

      def on(event, &handler)
        @target.on(namespaced(event), &handler)
      end

      def one(event, &handler)
        @target.one(namespaced(event), &handler)
      end

      def off(event = nil, handler = nil, &block)
        return @target.off unless event

        @target.off(namespaced(event), handler, &block)
      end

      def trigger(event, *args, **params)
        @target.trigger(namespaced(event), *args, **params)
      end

      def send(event, **params)
        @target.send(namespaced(event), **params)
      end

      private

      def namespaced(event)
        "#{@name}:#{event}"
      end
    end
  end
end
