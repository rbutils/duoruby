# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"
require "duoruby/setup/backend"

RSpec.describe "DuoRuby.boot" do
  it "loads optional root config before the default setup file" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, "duoruby.rb"), "$duoruby_boot_order = [:config]\n")
      FileUtils.mkdir_p(File.join(root, "app", "setup"))
      File.write(File.join(root, "app", "setup", "backend.rb"), "$duoruby_boot_order << :backend\n")

      loaded = DuoRuby.boot(:backend, root: root)

      loaded.map { |path| path.delete_prefix(root) }.should == ["/duoruby.rb", "/app/setup/backend.rb"]
      $duoruby_boot_order.should == [:config, :backend]
    ensure
      $duoruby_boot_order = nil
    end
  end
end
