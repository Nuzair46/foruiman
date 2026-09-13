# frozen_string_literal: true

# Foreman's assignment and quoting rules, with a non-mutating merge API.
class Foruiman::Env
  def initialize(filename)
    @entries = File.read(filename).gsub("\r\n", "\n").split("\n").each_with_object({}) do |line, result|
      next unless (match = line.match(/\A([A-Za-z_0-9]+)=(.*)\z/))

      key, value = match.captures
      result[key] = case value
                    when /\A'(.*)'\z/ then Regexp.last_match(1)
                    when /\A"(.*)"\z/ then Regexp.last_match(1).gsub('\\n', "\n").gsub(/\\(.)/, '\1')
                    else value
                    end
    end
  end

  def entries(&block)
    return @entries.each unless block

    @entries.each(&block)
  end

  def to_h
    @entries.dup
  end

  def self.load(root: Dir.pwd, file: nil, dotenv: true, inherited: ENV.to_h)
    env = inherited.dup
    default = File.join(root, ".env")
    if file
      Array(file).each { |filename| env.merge!(new(filename).to_h) }
    elsif dotenv && File.file?(default)
      env.merge!(new(default).to_h)
    end
    env.transform_values { |value| value.dup.freeze }.freeze
  end
end
