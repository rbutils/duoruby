# frozen_string_literal: true

module DuoRuby
  # A named set of clients that can be messaged as a unit.
  #
  # Groups provide the broadcast primitive for server-side pub/sub. Membership
  # is bidirectional: the group tracks its members, and each {Client} tracks
  # which groups it belongs to. This makes it cheap to remove a client from
  # all its groups on disconnect without iterating every group.
  #
  # Groups are created lazily by {Backend#group} and are keyed by symbol name.
  #
  # @example Adding a client to a group and broadcasting
  #   backend.group(:lobby) << client
  #   backend.group(:lobby).send(:announcement, text: "Server restart in 5 min")
  class Group
    class Selection
      def initialize(members)
        @members = members
      end

      def send(event, **params)
        @members.each { |client| client.send(event, **params) }
        self
      end
    end

    # @return [Symbol] the group's name
    attr_reader :name

    # @return [Array<Client>] current members, in the order they joined
    attr_reader :members

    # @param name [String, Symbol] the group name; stored as a Symbol
    def initialize(name)
      @name = name.to_sym
      @members = []
    end

    # Adds +client+ to the group (no-op if already a member).
    # Also registers this group in +client.groups+.
    #
    # @param client [Client]
    # @return [self]
    def add(client)
      members << client unless members.include?(client)
      client.groups[name] = self
      self
    end

    # Shovel operator — same as {#add}.
    alias << add

    # Removes +client+ from the group and unregisters the group from +client.groups+.
    #
    # @param client [Client]
    # @return [Client] the removed client
    def remove(client)
      members.delete(client)
      client.groups.delete(name)
      client
    end

    def include?(client)
      members.include?(client)
    end

    def size
      members.size
    end

    def empty?
      members.empty?
    end

    def except(*clients)
      Selection.new(members - clients)
    end

    def send_to_others(client, event, **params)
      except(client).send(event, **params)
      self
    end

    # Sends +event+ with +params+ to every current member.
    #
    # @param event [String, Symbol] the event name
    # @param params keyword arguments forwarded to each {Client#send}
    # @return [self]
    def send(event, **params)
      members.each { |client| client.send(event, **params) }
      self
    end
  end
end
