# frozen_string_literal: true

module Foruiman::TUI
  class Keyboard
    SEQUENCES = {
      "\e[A" => :up, "\e[B" => :down, "\e[C" => :next, "\e[D" => :previous,
      "\e[5~" => :page_up, "\e[6~" => :page_down, "\e[H" => :home, "\e[F" => :end,
      "\e[1~" => :home, "\e[4~" => :end, "\eOH" => :home, "\eOF" => :end,
      "\e[Z" => :previous
    }.freeze
    KEYS = {
      "\t" => :next, "h" => :previous, "l" => :next, "k" => :up, "j" => :down,
      "g" => :home, "G" => :end, "f" => :follow, " " => :toggle_follow,
      "r" => :restart, "R" => :restart_all, "s" => :stop, "S" => :stop_all,
      "i" => :input, "?" => :help, "q" => :quit, "\x03" => :quit,
      "\x15" => :page_up, "\x04" => :page_down
    }.freeze

    def initialize
      @buffer = +"".b
      @escape_at = nil
    end

    def feed(bytes, now: monotonic)
      @buffer << bytes
      actions = []
      until @buffer.empty?
        if @buffer.start_with?("\e")
          sequence = SEQUENCES.keys.find { |key| @buffer.start_with?(key) }
          if sequence
            actions << SEQUENCES.fetch(sequence)
            @buffer.slice!(0, sequence.bytesize)
          elsif incomplete_escape?
            @escape_at ||= now
            break if now - @escape_at < 0.1 && @buffer.bytesize < 64

            actions << :escape if @buffer == "\e"
            @buffer.clear
          else
            # Ignore an unknown complete escape as a unit; its final byte must
            # never accidentally become a destructive shortcut such as R.
            match = @buffer.match(%r{\A\e(?:\[[0-?]*[ -/]*[@-~]|O.|.)}m)
            @buffer.slice!(0, match ? match[0].bytesize : 1)
          end
        else
          key = @buffer.slice!(0, 1)
          actions << (key.match?(/[0-9]/) ? key.to_i : KEYS[key])
        end
        @escape_at = nil
      end
      actions.compact
    end

    private

    def incomplete_escape?
      return true if @buffer == "\e" || @buffer == "\eO"

      @buffer.start_with?("\e[") && !@buffer.match?(%r{\A\e\[[0-?]*[ -/]*[@-~]})
    end

    def monotonic
      ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    end
  end
end
