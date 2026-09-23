# frozen_string_literal: true

require "thor"
require "foruiman"
require_relative "plain"
require_relative "diagnostics"
require_relative "configuration"

# Foreman's Thor command structure with an interactive supervisor.
class Foruiman::CLI < Thor
  map ["-v", "--version"] => :version
  default_task :start
  check_unknown_options!
  remove_command :tree

  class_option :procfile, type: :string, aliases: "-f", desc: "Procfile to read (default: Procfile)"
  class_option :root, type: :string, aliases: "-d", desc: "Working directory (default: Procfile directory)"
  class_option :env, type: :string, aliases: "-e", desc: "Comma-separated environment files instead of .env"
  class_option :dotenv, type: :boolean, desc: "Load default .env when -e is absent (default: true)"
  class_option :port, type: :string, aliases: "-p", desc: "Base port (default: PORT or 5000)"
  class_option :log_lines, type: :string, desc: "Maximum records per process and in all (default: 10000)"
  class_option :timeout, type: :string, aliases: "-t", desc: "Seconds before escalating TERM to KILL (default: 5)"
  class_option :exit_on, type: :string, desc: "Shutdown policy: all, any, failure (default: all)"

  def self.is_thor_reserved_word?(word, type) # rubocop:disable Naming/PredicatePrefix -- Thor's extension API
    word == "run" ? false : super
  end

  def self.exit_on_failure?
    true
  end

  desc "start [PROCESS]", "Run the Procfile with process tabs, or stream logs without a TTY"
  method_option :tui, type: :boolean, desc: "Use the terminal interface when stdin and stdout are TTYs (default: true)"
  def start(process = nil)
    engine = build_engine
    engine.select(process) if process
    interactive = configuration.tui? && $stdin.tty? && $stdout.tty?
    diagnostics = Foruiman::Diagnostics.new(interactive: interactive)
    code = if interactive
             require_relative "tui/application"
             Foruiman::TUI::Application.new(engine).run
           else
             Foruiman::Plain.new(engine).run
           end
    exit(code)
  rescue Foruiman::Error, SystemCallError => e
    raise Thor::Error, e.message
  rescue StandardError => e
    diagnostics&.error(e)
    warn "foruiman: #{e.message}#{" (details: #{diagnostics.path})" if diagnostics&.path}"
    exit(1)
  ensure
    engine&.close
    diagnostics&.close
  end

  desc "run COMMAND [ARGS...]", "Run a command or Procfile entry with the application's environment"
  stop_on_unknown_option! :run
  def run(*args)
    raise Foruiman::Error, "run requires a command" if args.empty?

    config = configuration
    env = config.environment
    command = Foruiman::Procfile.new(config.procfile)[args.first] if args.size == 1 && File.file?(config.procfile)
    if command
      exec(env, "/bin/sh", "-c", command, chdir: config.root, unsetenv_others: true)
    else
      # Preserve argv, terminal input, signals and the command's exact exit code.
      exec(env, [args.first, args.first], *args.drop(1), chdir: config.root, unsetenv_others: true)
    end
  rescue Foruiman::Error, SystemCallError => e
    raise Thor::Error, e.message
  end

  desc "check", "Validate the Procfile, environment files, ports, and log capacity without starting processes"
  def check
    engine = build_engine
    puts "valid Procfile (#{engine.process_names.join(', ')})"
  rescue Foruiman::Error, SystemCallError => e
    raise Thor::Error, e.message
  ensure
    engine&.close
  end

  desc "version", "Display Foruiman gem version"
  def version
    puts Foruiman::VERSION
  end

  private

  def configuration
    @configuration ||= Foruiman::Configuration.new(options)
  end

  def build_engine
    config = configuration
    env = config.environment
    Foruiman::Engine.new(procfile: config.procfile, root: config.root, env: env,
                         port: config.port(env), log_lines: config.log_lines,
                         term_timeout: config.timeout, exit_on: config.exit_on)
  end
end
