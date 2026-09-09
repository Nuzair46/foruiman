# frozen_string_literal: true

require_relative "lib/foruiman/version"

Gem::Specification.new do |spec|
  spec.name = "foruiman"
  spec.version = Foruiman::VERSION
  spec.authors = ["Foruiman contributors", "David Dollar"]
  spec.summary = "A Procfile supervisor with process tabs, bounded logs, and isolated restarts"
  spec.description = "Run a Procfile in a terminal interface or a plain stream. Derived from Foreman."
  spec.license = "MIT"
  spec.homepage = "https://github.com/Nuzair46/foruiman"
  spec.required_ruby_version = ">= 3.2"
  spec.files = Dir["lib/**/*.rb", "bin/foruiman", "README.md", "LICENSE", "CHANGELOG.md", "docs/*.{md,png}"]
  spec.bindir = "bin"
  spec.executables = ["foruiman"]
  spec.require_paths = ["lib"]
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["source_code_uri"] = "https://github.com/Nuzair46/foruiman"
  spec.metadata["changelog_uri"] = "https://github.com/Nuzair46/foruiman/blob/main/CHANGELOG.md"
  spec.add_dependency "thor", ">= 1.3", "< 2"
  spec.add_dependency "unicode-display_width", ">= 3.1", "< 4"
end
