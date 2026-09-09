# frozen_string_literal: true

require "thor"
require "foruiman"
require_relative "plain"
require_relative "diagnostics"

# Foreman's Thor command structure, reduced to the MVP surface.
class Foruiman::CLI < Thor
  map ["-v", "--version"] => :version
  default_task :start
  check_unknown_options!
  remove_command :tree

  class_option :procfile, type: :string, aliases: "-f", default: "Procfile", desc: "Procfile to read"
  class_option :root, type: :string, aliases: "-d", desc: "Working directory (default: invocation directory)"
  class_option :env, type: :string, aliases: "-e", desc: "Environment file layered after .env"
  class_option :dotenv, type: :boolean, default: true, desc: "Load optional .env from working directory"
  class_option :port, type: :string, aliases: "-p", default: "5000", desc: "Base port (increments by 100)"
  class_option :log_lines, type: :string, default: "10000", desc: "Maximum records per process and in all"

  def self.exit_on_failure?
    true
  end

  desc "start [PROCESS]", "Run the Procfile with process tabs, or stream logs without a TTY"
  method_option :tui, type: :boolean, default: true, desc: "Use the terminal interface when stdin and stdout are TTYs"
  def start(process = nil)
    engine = build_engine
    engine.select(process) if process
    interactive = options[:tui] && $stdin.tty? && $stdout.tty?
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

  def integer_option(name)
    text = options.fetch(name).to_s
    raise Foruiman::Error, "#{name.to_s.tr('_', '-')} must be a positive integer" unless text.match?(/\A[0-9]+\z/)

    text.to_i
  end

  def build_engine
    root = File.expand_path(options[:root] || Dir.pwd)
    procfile = File.expand_path(options[:procfile], root)
    file = File.expand_path(options[:env], root) if options[:env]
    env = Foruiman::Env.load(root: root, file: file, dotenv: options[:dotenv])
    Foruiman::Engine.new(procfile: procfile, root: root, env: env,
                         port: integer_option(:port), log_lines: integer_option(:log_lines))
  end
end
