# frozen_string_literal: true

require "yaml"

class Foruiman::Configuration
  OPTIONS = %w[procfile root env dotenv port log_lines timeout exit_on tui].freeze
  BOOLEAN_OPTIONS = %w[dotenv tui].freeze
  PATH_OPTIONS = %w[procfile root env].freeze

  def initialize(options, directory: Dir.pwd)
    @directory = directory
    @options = defaults.merge(options.to_h.transform_keys { |key| key.to_s.tr("-", "_") })
    BOOLEAN_OPTIONS.each do |key|
      next unless @options.key?(key)
      next if [true, false].include?(@options[key])

      raise Foruiman::Error, "#{key}: expected true or false"
    end
    PATH_OPTIONS.each do |key|
      next unless @options.key?(key)
      next if @options[key].is_a?(String) && !@options[key].empty?

      raise Foruiman::Error, "#{key}: expected a nonempty path"
    end
  end

  def procfile
    # Foreman's explicit -f is relative to invocation, independently of -d.
    File.expand_path(@options.fetch("procfile", File.join(@options.fetch("root", "."), "Procfile")), @directory)
  end

  def root
    File.expand_path(@options.fetch("root", File.dirname(procfile)), @directory)
  end

  def environment
    # Foreman loads the default environment before inferring a root from -f.
    env_root = File.expand_path(@options.fetch("root", "."), @directory)
    files = @options["env"]&.split(",", -1)&.map do |file|
      raise Foruiman::Error, "env: expected comma-separated file paths" if file.empty?

      File.expand_path(file, @directory)
    end
    Foruiman::Env.load(root: env_root, file: files, dotenv: @options.fetch("dotenv", true))
  end

  def port(env)
    integer("port", @options.fetch("port") { env.fetch("PORT", "5000") })
  end

  def log_lines
    integer("log_lines", @options.fetch("log_lines", "10000"))
  end

  def timeout
    value = Float(@options.fetch("timeout", 5), exception: false)
    return value if value&.finite? && value >= 0

    raise Foruiman::Error, "timeout must be a finite nonnegative number"
  end

  def exit_on
    value = @options.fetch("exit_on", "all")
    return value.to_sym if %w[all any failure].include?(value)

    raise Foruiman::Error, "exit-on must be all, any, or failure"
  end

  def tui?
    @options.fetch("tui", true)
  end

  private

  def integer(name, value)
    text = value.to_s
    unless text.match?(/\A[0-9]+\z/) && text.to_i.positive?
      raise Foruiman::Error, "#{name.tr('_', '-')} must be a positive integer"
    end

    text.to_i
  end

  def defaults
    path = File.join(@directory, ".foreman")
    return {} unless File.file?(path)

    values = YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: false)
    return {} if values.nil?
    raise Foruiman::Error, "#{path}: expected a YAML mapping of option names to values" unless values.is_a?(Hash)

    values.each_with_object({}) do |(key, value), result|
      name = key.to_s.tr("-", "_")
      raise Foruiman::Error, "#{path}: unsupported option #{key.inspect}" unless OPTIONS.include?(name)

      result[name] = value
    end
  rescue Psych::Exception => e
    raise Foruiman::Error, "#{path}: #{e.message}"
  end
end
