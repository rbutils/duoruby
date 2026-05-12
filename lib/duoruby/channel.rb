# frozen_string_literal: true

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

    class Namespace
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

    # Provides class-level (and module-level) event handler registration.
    #
    # When included in a module or class, HandlerMethods also *extends* that
    # receiver with itself, making {#on}, {#one}, {#off}, and {#handlers}
    # available as class/module methods.
    #
    # When a module that uses HandlerMethods is subsequently included into a
    # class, the {#included} hook copies the module's declared handlers into
    # the receiver via {#merge_handlers}.
    #
    # @example Mixing into a plain module
    #   module Greetings
    #     include DuoRuby::Channel::HandlerMethods
    #     on(:hello) { puts "hi!" }
    #   end
    #
    #   class MyChannel < DuoRuby::Channel
    #     include Greetings
    #   end
    module HandlerMethods
      # @private
      def self.included(receiver)
        receiver.extend(self)
      end

      # @return [Hash{String => Array<Handler>}] the declared handlers for this class/module
      def handlers
        @handlers ||= {}
      end

      # Registers a persistent handler for +event+.
      #
      # @param event [String, Symbol] the event name to listen for;
      #   use +"*"+ / +:*+ to match every event
      # @yieldparam args positional arguments forwarded by {Channel#dispatch}
      # @yieldparam params keyword arguments forwarded by {Channel#dispatch}
      # @return [Handler] a token that can be passed to {#off} to remove this handler
      def on(event, &handler)
        add_handler(event, false, &handler)
      end

      # Registers a one-shot handler for +event+.
      # The handler is automatically removed after the first time it fires.
      #
      # @param event [String, Symbol] the event name
      # @yieldparam args positional arguments forwarded by {Channel#dispatch}
      # @yieldparam params keyword arguments forwarded by {Channel#dispatch}
      # @return [Handler] a token that can be passed to {#off} to remove this handler
      def one(event, &handler)
        add_handler(event, true, &handler)
      end

      # Removes handlers. Behaviour depends on the arguments:
      #
      # - No args — removes *all* handlers
      # - +event+ only — removes all handlers for that event
      # - +event+ + proc or +event+ + block — removes the specific handler matching by proc identity
      # - Handler token (from {#on}/{#one}) — removes that specific registration
      #
      # @overload off
      # @overload off(event)
      #   @param event [String, Symbol]
      # @overload off(event, handler)
      #   @param event [String, Symbol]
      #   @param handler [Proc]
      # @overload off(token)
      #   @param token [Handler] the value returned by {#on} or {#one}
      def off(event = nil, handler = nil, &block)
        remove_handler(handlers, event, handler || block)
      end

      def channel(name)
        Namespace.new(self, name)
      end

      # @private — called when a module using HandlerMethods is included into a class.
      # Merges the module's declared handlers into the receiver.
      def included(receiver)
        receiver.__send__(:merge_handlers, handlers)
        super if defined?(super)
      end

      protected

      # Creates a new Handler and appends it to +handlers+ for +event+.
      # @return [Handler]
      def add_handler(event, once, &handler)
        raise ArgumentError, "handler required" unless handler

        event = normalize_event(event)
        handlers[event] ||= []
        Handler.new(event, handler, once).tap { |registered| handlers[event] << registered }
      end

      # Deep-merges +other_handlers+ into a fresh clone of the current handlers.
      # Used by the +inherited+ and +included+ hooks to propagate declared handlers
      # down the inheritance chain without sharing mutable state.
      def merge_handlers(other_handlers)
        @handlers = clone_handlers(handlers)
        other_handlers.each do |event, event_handlers|
          @handlers[event] ||= []
          @handlers[event].concat(event_handlers.map { |h| Handler.new(h.event, h.block, h.once) })
        end
      end

      # Returns a deep copy of +source+ where every Handler struct is a new object.
      # @param source [Hash{String => Array<Handler>}]
      # @return [Hash{String => Array<Handler>}]
      def clone_handlers(source)
        source.each_with_object({}) do |(event, event_handlers), cloned|
          cloned[event] = event_handlers.map { |h| Handler.new(h.event, h.block, h.once) }
        end
      end

      # Normalises an event name to a String.
      def normalize_event(event)
        event.to_s
      end

      # Removes handlers from +source+ according to the given criteria.
      # See the public {#off} for the full removal semantics.
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

      # Returns true if +registered+ matches +handler+ by object or block identity.
      def same_handler?(registered, handler)
        return registered.equal?(handler) || registered.block.equal?(handler.block) if handler.is_a?(Handler)

        registered.block.equal?(handler)
      end
    end

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
