# frozen_string_literal: true

require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

begin
  require "opal/rspec/rake_task"
  require "opal-browser"

  Opal::RSpec::RakeTask.new(:opal_spec) do |server, task|
    server.append_path "lib"
    server.append_path "spec/opal"
    task.default_path = "spec/opal"
    task.pattern = "spec/opal/**/*_spec.rb"
  end
rescue LoadError
  task :opal_spec do
    warn "opal-rspec is not installed. Run bundle install first."
    exit false
  end
end

task default: :spec
