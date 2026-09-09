# frozen_string_literal: true

# Adapted from Foreman::Process. Expansion belongs to the shell, not Ruby.
class Foruiman::Process
  attr_reader :command, :env, :cwd

  def initialize(command, options = {})
    @command = command.dup.freeze
    @env = (options[:env] || ENV.to_h).dup.freeze
    @cwd = File.expand_path(options[:cwd] || Dir.pwd)
  end

  def run(options = {})
    ::Process.spawn(env.merge(options.fetch(:env, {})), "/bin/sh", "-c", command,
                    chdir: cwd, in: File::NULL, out: options.fetch(:output, $stdout),
                    err: options.fetch(:error, $stderr), pgroup: true, unsetenv_others: true,
                    close_others: true)
  end
end
