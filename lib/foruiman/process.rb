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
    environment = env.merge(options.fetch(:env, {}))
    redirects = { chdir: cwd, in: options.fetch(:input, $stdin), out: options.fetch(:output, $stdout),
                  err: options.fetch(:error, $stderr), unsetenv_others: true, close_others: true }
    return spawn_session(environment, redirects) if options[:new_session]

    ::Process.spawn(environment, "/bin/sh", "-c", shell_command, **redirects, pgroup: true)
  end

  private

  def shell_command
    # Group forwarding also reaches the shell waiting for the application.
    # Catch (rather than ignore) these signals so exec resets the dispositions
    # and the application can decide whether to handle them or terminate.
    "trap ':' USR1 USR2\n#{command}"
  end

  def spawn_session(environment, redirects)
    # A background group in the supervisor's session cannot read its controlling
    # terminal. A new session keeps inherited stdin usable and still gives us a
    # group whose ID is the child PID, without taking the terminal's foreground.
    reader, writer = IO.pipe
    writer.close_on_exec = true
    pid = ::Process.fork do
      reader.close
      ::Process.setsid
      exec(environment, "/bin/sh", "-c", shell_command, **redirects)
    rescue Exception => e # rubocop:disable Lint/RescueException -- never unwind the fork into supervisor cleanup
      writer.write("#{e.is_a?(SystemCallError) ? e.errno : 0}\n#{e.message}")
    ensure
      ::Process.exit!(127)
    end
    writer.close
    failure = reader.read
    unless failure.empty?
      ::Process.waitpid(pid)
      errno, message = failure.split("\n", 2)
      raise ArgumentError, message if errno.to_i.zero?

      raise SystemCallError.new(message, errno.to_i)
    end
    pid
  ensure
    [reader, writer].compact.each { |io| io.close unless io.closed? }
  end
end
