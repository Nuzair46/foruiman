# frozen_string_literal: true

require "tmpdir"
require "open3"
require "rbconfig"
require "shellwords"
require_relative "../lib/foruiman/version"

archive = File.expand_path(ARGV.fetch(0, "foruiman-#{Foruiman::VERSION}.gem"))
Dir.mktmpdir("foruiman-gem-smoke-") do |directory|
  install = File.join(directory, "gems")
  # Dependencies are supplied by bundle install; install only the built artifact.
  success = system(RbConfig.ruby, "-S", "gem", "install", "--local", archive,
                   "--install-dir", install, "--no-document", "--ignore-dependencies")
  abort "gem installation failed" unless success

  env = { "GEM_HOME" => install, "GEM_PATH" => [install, *Gem.path].join(File::PATH_SEPARATOR),
          "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil }
  executable = File.join(install, "bin", "foruiman")
  ruby_command = [RbConfig.ruby, "-e", 'puts "packaged gem works"'].shelljoin
  File.write(File.join(directory, "Procfile"), "web: #{ruby_command}\n")
  stdout, stderr, status = Open3.capture3(env, executable, "start", "--no-tui", chdir: directory)
  abort "installed gem failed: #{stdout}\n#{stderr}" unless status.success? && stdout.include?("packaged gem works")

  puts "Installed gem smoke test passed"
end
