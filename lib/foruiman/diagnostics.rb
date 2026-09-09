# frozen_string_literal: true

class Foruiman::Diagnostics
  attr_reader :path

  def initialize(interactive:, stderr: $stderr)
    @interactive = interactive
    @temporary = nil
    @output = stderr
  end

  def error(exception)
    if @interactive && !@temporary
      require "tempfile"
      @temporary = Tempfile.create(["foruiman-", ".log"])
      @temporary.chmod(0o600)
      @output = @temporary
      @path = @temporary.path
    end
    @output.puts(exception.full_message(highlight: false))
    @output.flush
  end

  def close
    @temporary&.close
  end
end
