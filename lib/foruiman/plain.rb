# frozen_string_literal: true

class Foruiman::Plain
  def initialize(engine, output: $stdout)
    @engine = engine
    @output = output
  end

  def run
    @engine.on_event do |event|
      record = event.record
      next unless record&.complete

      text = record.text.gsub(Foruiman::ANSI::SGR, "")
      @output.puts "#{record.time.strftime('%H:%M:%S')} #{record.name} [#{record.stream}] | #{text}"
      @output.flush
    end
    @engine.run
  rescue Errno::EPIPE
    0
  end
end
