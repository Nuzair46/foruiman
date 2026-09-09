# frozen_string_literal: true

require "io/console"

module Foruiman::TUI
  class Terminal
    ENTER = "\e[?1049h\e[?25l\e[0m"
    LEAVE = "\e[0m\e[?25h\e[?1049l"

    def initialize(input: $stdin, output: $stdout)
      @input = input
      @output = output
    end

    def session(&)
      @output.write(ENTER)
      @output.flush
      @input.raw(intr: false, &)
    ensure
      begin
        @output.write(LEAVE)
        @output.flush
      rescue IOError, SystemCallError
        # Input's raw block has already restored its exact prior terminal mode.
      end
    end

    def size
      rows, columns = @output.winsize
      [[rows, 1].max, [columns, 1].max]
    rescue IOError, SystemCallError
      [24, 80]
    end

    def read
      @input.read_nonblock(4096, exception: false)
    end

    def draw(frame)
      @output.write(frame)
      @output.flush
    end
  end
end
