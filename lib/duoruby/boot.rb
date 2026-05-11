# frozen_string_literal: true

require "duoruby/config"

module DuoRuby
  # Application bootstrapping helpers.
  #
  # These methods locate and load the two conventional application files for a
  # given side (+:backend+ or +:frontend+):
  #
  #   <root>/duoruby.rb               # optional shared config
  #   <root>/app/<side>/setup.rb      # side-specific entry point
  #
  # They also ensure the application's root and +app/+ directories are on
  # +$LOAD_PATH+ so application code can +require+ its own files without
  # specifying full paths.

  # Loads the application files for +side+ from +root+, adding the root and
  # +app/+ directories to +$LOAD_PATH+ first.
  #
  # Uses +Kernel#load+ for both files so they are always re-evaluated (rather
  # than skipped if previously required). Both files are optional — only those
  # that exist are loaded.
  #
  # @param side [:backend, :frontend] which side to boot
  # @param root [String] the application root directory (defaults to +Dir.pwd+)
  # @return [Array<String>] absolute paths of the files that were loaded
  def self.boot(side = :backend, root: Dir.pwd)
    root = prepare_root(root)
    paths = app_paths(side, root: root)

    paths = paths.select { |path| File.file?(path) }
    paths.each { |path| load path }
    paths
  end

  # Loads the application files for +side+ and returns the registered app object.
  #
  # This is a CRuby/server-side method — it is never run inside an Opal
  # compiled bundle. Both files are loaded with +Kernel#load+ (a runtime file
  # loader that accepts a computed path) rather than +require+.
  #
  # The setup file is expected to call +DuoRuby.app = <instance>+ to register
  # the backend it creates. {.load_app} returns that registered value and clears
  # the slot so successive calls in the same process behave independently.
  #
  # @param side [:backend, :frontend] which side to load
  # @param root [String] the application root directory
  # @return [Object, nil] the value passed to +DuoRuby.app=+, or +nil+ if the
  #   setup file does not exist or no app was registered
  def self.load_app(side = :backend, root: Dir.pwd)
    root = prepare_root(root)
    config_path = File.join(root, "duoruby.rb")
    load config_path if File.file?(config_path)

    setup_path = File.join(root, "app", side.to_s, "setup.rb")
    return unless File.file?(setup_path)

    load setup_path
    @app.tap { @app = nil }
  end

  # Registers the application instance produced by a setup file.
  # Called from within +app/<side>/setup.rb+; the registered value is read
  # back by {.load_app} and then cleared.
  #
  # @param instance [Object] the backend or frontend instance
  def self.app=(instance)
    @app = instance
  end

  # Expands +root+ to an absolute path and prepends both +<root>+ and
  # +<root>/app+ to +$LOAD_PATH+ (unless already present).
  #
  # @param root [String] the raw root path
  # @return [String] the expanded absolute root path
  def self.prepare_root(root)
    root = File.expand_path(root)
    [File.join(root, "app"), root].each do |path|
      $LOAD_PATH.unshift(path) unless $LOAD_PATH.include?(path)
    end

    root
  end

  # Returns the canonical pair of application file paths for +side+.
  #
  # @param side [:backend, :frontend]
  # @param root [String] the application root directory
  # @return [Array<String, String>] +[config_path, setup_path]+
  def self.app_paths(side, root: Dir.pwd)
    root = File.expand_path(root)
    [File.join(root, "duoruby.rb"), File.join(root, "app", side.to_s, "setup.rb")]
  end
end
