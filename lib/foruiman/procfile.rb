# frozen_string_literal: true

# Derived from Foreman's ordered Procfile reader/writer; see docs/UPSTREAM.md.
class Foruiman::Procfile
  class ParseError < Foruiman::Error
  end

  class EmptyFileError < ParseError
  end

  def initialize(filename = nil)
    @entries = []
    load(filename) if filename
  end

  def entries(&block)
    return @entries.each unless block

    @entries.each(&block)
  end

  def [](name)
    @entries.find { |key, _command| key == name }&.last
  end

  def []=(name, command)
    validate_entry!(name, command, "Procfile entry")
    delete(name)
    @entries << [name.freeze, command.freeze].freeze
  end

  def delete(name)
    @entries.reject! { |key, _command| key == name }
  end

  def load(filename)
    parsed = parse(filename)
    raise EmptyFileError, "#{filename}: no processes defined" if parsed.empty?

    @entries.replace(parsed)
    self
  end

  def save(filename)
    File.write(filename, "#{self}\n")
  end

  def to_s
    @entries.map { |name, command| "#{name}: #{command}" }.join("\n")
  end

  private

  def validate_entry!(name, command, location)
    unless name.match?(/\A[A-Za-z0-9_-]+\z/) && !command.strip.empty? && !command.include?("\0")
      raise ParseError, "#{location}: expected NAME: command"
    end
    raise ParseError, "#{location}: 'all' is reserved for the aggregate tab" if name == "all"
  end

  def parse(filename)
    seen = {}
    File.read(filename, encoding: "UTF-8").lines.filter_map.with_index(1) do |line, number|
      line = line.delete_suffix("\n").delete_suffix("\r")
      next if line.strip.empty? || line.lstrip.start_with?("#")

      location = "#{filename}:#{number}"
      match = line.match(/\A([A-Za-z0-9_-]+):[ \t]*(.*)\z/)
      raise ParseError, "#{location}: expected NAME: command" unless match

      name, command = match.captures
      validate_entry!(name, command, location)
      raise ParseError, "#{location}: duplicate '#{name}' (first defined on line #{seen[name]})" if seen[name]

      seen[name] = number
      [name.freeze, command.freeze].freeze
    end
  rescue ArgumentError => e
    raise ParseError, "#{filename}: #{e.message}"
  end
end
