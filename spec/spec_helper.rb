# frozen_string_literal: true

require "foruiman"
require "tmpdir"
require "fileutils"
require "timeout"
require "rbconfig"
require "shellwords"
require "open3"

module SpecHelpers
  def write_file(name, content)
    filename = File.join(@directory, name)
    FileUtils.mkdir_p(File.dirname(filename))
    File.write(filename, content)
    filename
  end

  def fixture(mode, *args)
    [RbConfig.ruby, File.expand_path("fixtures/child.rb", __dir__), mode, *args].shelljoin
  end

  def build_engine(entries = {}, **)
    engine = Foruiman::Engine.new(root: @directory, term_timeout: 0.15, **)
    @engines << engine
    entries.each { |name, command| engine.register(name, command) }
    engine
  end

  def eventually(engine = nil, timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      raise "condition timed out after #{timeout}s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      engine ? engine.tick(timeout: 0.01) : sleep(0.01)
    end
  end

  def alive?(pid)
    Process.kill(0, pid)
    state = File.read("/proc/#{pid}/stat").rpartition(") ").last.split.first if RUBY_PLATFORM.include?("linux")
    return false if %w[Z X].include?(state)

    true
  rescue Errno::ESRCH, Errno::ENOENT
    false
  end

  def cli(*, env: {})
    Open3.capture3(env, RbConfig.ruby, "-I", File.expand_path("../lib", __dir__),
                   File.expand_path("../bin/foruiman", __dir__), *, chdir: @directory)
  end
end

RSpec.configure do |config|
  config.include SpecHelpers
  config.around do |example|
    Dir.mktmpdir("foruiman-spec-") do |directory|
      @directory = directory
      @engines = []
      begin
        example.run
      ensure
        @engines.each(&:close)
      end
    end
  end
end
