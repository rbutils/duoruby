# frozen_string_literal: true

require "opal"
require "opal/builder"
require "opal-browser"
require "duoruby/config"

module DuoRuby
  class Server
    class FrontendCompiler
      def initialize(root)
        @root = root
      end

      def call
        Opal.reset_paths!
        Opal.use_gem("opal-browser")
        Opal.use_gem("paggio")
        Opal.append_path(File.join(Gem::Specification.find_by_name("opal-browser").gem_dir, "opal"))
        append_frontend_gems

        builder = Opal::Builder.new
        builder.stubs.concat(DuoRuby.config.frontend_stubs)
        builder.append_paths(File.join(@root, "app"), File.expand_path("../..", __dir__))
        builder.build("opal")
        builder.build("setup/frontend")
        builder.to_s
      end

      private

      def append_frontend_gems
        DuoRuby.config.frontend_gems.each do |gem_name|
          Opal.use_gem(gem_name)
          spec = Gem::Specification.find_by_name(gem_name)
          opal_dir = File.join(spec.gem_dir, "opal")
          Opal.append_path(opal_dir) if File.directory?(opal_dir)
        end
      end
    end
  end
end
