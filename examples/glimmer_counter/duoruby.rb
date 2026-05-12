DuoRuby.configure do |c|
  c.title = "Counter"
  c.frontend_gems = %w[glimmer-dsl-web opal-async opal-jquery to_collection]
  # lib/opal/async.rb is a CRuby-only build helper (calls Opal.append_path);
  # stub it so it compiles as empty and never runs in the browser.
  c.frontend_stubs = %w[opal/async]
end
