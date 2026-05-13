# frozen_string_literal: true

require "duoruby/channel/namespace"
require "duoruby/channel/handler_methods"

module DuoRuby
  # Base class for event-driven components in DuoRuby.
  #
  # Channel provides a flexible pub/sub event system with support for:
  # - Class-level handler declarations that are inherited by subclasses
  # - Module-level handler declarations that merge into including classes
  # - Per-instance handler isolation (class handlers are deep-cloned on initialize)
  # - One-shot handlers via {#one}
  # - Wildcard handlers that run on every event via {#on} with the +*+ event name
  # - Removal by event name, proc reference, or Handler token
  #
  # {Backend} and {Frontend} both inherit from Channel.
  #
  # @example Declaring handlers at the class level (inherited by instances)
  #   class MyBackend < DuoRuby::Backend
  #     on(:join) { |client, room:| group(room) << client }
  #   end
  #
  # @example Adding handlers on an instance
  #   backend = MyBackend.new
  #   token = backend.on(:join) { |client, room:| puts "#{client.id} joined #{room}" }
  #   backend.off(token)  # remove by token
  class Channel
    # @return [Hash{String => Array<Handler>}] the event-to-handlers map for this object
    attr_reader :handlers

    # Internal record tying a block to its event and once-flag.
    # The value returned by {#on} and {#one} is a Handler; pass it to {#off}
    # to remove that specific registration.
    Handler = Struct.new(:event, :block, :once)

    extend HandlerMethods

    # Copies the parent class's handlers into the subclass when a subclass is defined.
    # @private
    def self.inherited(subclass)
      subclass.__send__(:merge_handlers, handlers)
      super
    end

    # Deep-clones the class-level handlers into this instance so that instance-level
    # {#on}/{#off} calls do not affect the class or other instances.
    def initialize
      @handlers = self.class.__send__(:clone_handlers, self.class.handlers)
    end

    # Registers a persistent instance-level handler for +event+.
    # Instance handlers stack on top of any class-level handlers that were
    # copied in at initialize time.
    #
    # @param event [String, Symbol] event name; use +"*"+ to match every event
    # @return [Handler] removal token
    def on(event, &handler)
      raise ArgumentError, "handler required" unless handler

      event = event.to_s
      handlers[event] ||= []
      Handler.new(event, handler, false).tap { |registered| handlers[event] << registered }
    end

    # Registers a one-shot instance-level handler for +event+.
    # Automatically removed after the first dispatch.
    #
    # @param event [String, Symbol] event name
    # @return [Handler] removal token
    def one(event, &handler)
      raise ArgumentError, "handler required" unless handler

      event = event.to_s
      handlers[event] ||= []
      Handler.new(event, handler, true).tap { |registered| handlers[event] << registered }
    end

    # Removes instance-level handlers. See {HandlerMethods#off} for the full
    # removal semantics — behaviour is identical at the instance level.
    def off(event = nil, handler = nil, &block)
      target = handler || block
      return handlers.clear unless event

      if event.is_a?(Handler)
        handlers[event.event]&.delete_if { |r| handler_identity?(r, event) }
        handlers.delete(event.event) if handlers[event.event]&.empty?
        return
      end

      event = event.to_s
      return handlers.delete(event) unless target

      handlers[event]&.delete_if { |r| handler_identity?(r, target) }
      handlers.delete(event) if handlers[event]&.empty?
    end

    def channel(name)
      Namespace.new(self, name)
    end

    # Returns a Proc wrapping the first registered handler for +event+, bound
    # to this instance via +instance_exec+. Returns +nil+ if no handler exists.
    # Used internally; may be useful for adapter integrations.
    #
    # @param event [String, Symbol]
    # @return [Proc, nil]
    def handler_for(event)
      event = event.to_s
      handler = handlers[event]&.first
      proc { |*args, **params| instance_exec(*args, **params, &handler.block) } if handler
    end

    # Dispatches +event+ to all registered handlers, then to any wildcard (+*+) handlers.
    #
    # All handlers are invoked via +instance_exec+ so they run in the context of
    # this Channel instance. Positional +args+ and keyword +params+ are forwarded
    # as-is. One-shot handlers are removed immediately after firing.
    #
    # @param event [String, Symbol] the event name
    # @param args positional arguments to forward (e.g. the client in Backend handlers)
    # @param params keyword arguments to forward (e.g. message params)
    # @return [nil]
    def dispatch(event, *args, **params)
      event = event.to_s
      results = dispatch_handlers(event, handlers[event], *args, **params)
      dispatch_handlers("*", handlers["*"], event, *args, **params)
      results
    end

    # Alias for {#dispatch}.
    alias trigger dispatch

    private

    # Checks handler identity by object identity (for Handler tokens) or
    # block proc identity (for raw Proc arguments).
    def handler_identity?(registered, handler)
      return registered.equal?(handler) || registered.block.equal?(handler.block) if handler.is_a?(Handler)

      registered.block.equal?(handler)
    end

    # Iterates over a snapshot of +event_handlers+, invoking each via +instance_exec+.
    # Removes one-shot handlers after they fire.
    def dispatch_handlers(event, event_handlers, *args, **params)
      return [] unless event_handlers

      event_handlers.dup.map do |handler|
        result = instance_exec(*args, **params, &handler.block)
        off(event, handler.block) if handler.once
        result
      end
    end
  end
end
