# frozen_string_literal: true

module DuoRuby
  class Channel
    module HandlerMethods
      def self.included(receiver)
        receiver.extend(self)
      end

      def handlers
        @handlers ||= {}
      end

      def on(event, &handler)
        add_handler(event, false, &handler)
      end

      def one(event, &handler)
        add_handler(event, true, &handler)
      end

      def off(event = nil, handler = nil, &block)
        remove_handler(handlers, event, handler || block)
      end

      def channel(name)
        Namespace.new(self, name)
      end

      def included(receiver)
        receiver.__send__(:merge_handlers, handlers)
        super if defined?(super)
      end

      protected

      def add_handler(event, once, &handler)
        raise ArgumentError, "handler required" unless handler

        event = normalize_event(event)
        handlers[event] ||= []
        Handler.new(event, handler, once).tap { |registered| handlers[event] << registered }
      end

      def merge_handlers(other_handlers)
        @handlers = clone_handlers(handlers)
        other_handlers.each do |event, event_handlers|
          @handlers[event] ||= []
          @handlers[event].concat(event_handlers.map { |h| Handler.new(h.event, h.block, h.once) })
        end
      end

      def clone_handlers(source)
        source.each_with_object({}) do |(event, event_handlers), cloned|
          cloned[event] = event_handlers.map { |h| Handler.new(h.event, h.block, h.once) }
        end
      end

      def normalize_event(event)
        event.to_s
      end

      def remove_handler(source, event = nil, handler = nil)
        return source.clear unless event

        if event.is_a?(Handler)
          source[event.event]&.delete_if { |registered| same_handler?(registered, event) }
          source.delete(event.event) if source[event.event]&.empty?
          return
        end

        event = normalize_event(event)
        return source.delete(event) unless handler

        source[event]&.delete_if { |registered| same_handler?(registered, handler) }
        source.delete(event) if source[event]&.empty?
      end

      def same_handler?(registered, handler)
        return registered.equal?(handler) || registered.block.equal?(handler.block) if handler.is_a?(Handler)

        registered.block.equal?(handler)
      end
    end
  end
end
