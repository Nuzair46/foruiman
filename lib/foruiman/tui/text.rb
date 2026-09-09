# frozen_string_literal: true

require "unicode/display_width"
require_relative "../ansi"

module Foruiman::TUI
  module Text
    module_function

    def width(text)
      Unicode::DisplayWidth.of(text.gsub(Foruiman::ANSI::SGR, ""), emoji: :all)
    end

    def clip(text, columns, ellipsis: false)
      return "" unless columns.positive?
      return text if width(text) <= columns

      limit = ellipsis ? columns - 1 : columns
      used = 0
      output = +""
      text.scan(/\e\[[0-9;:]*m|\X/).each do |token|
        if token.start_with?("\e[")
          output << token
          next
        end
        cells = Unicode::DisplayWidth.of(token, emoji: :all)
        break if used + cells > limit

        output << token
        used += cells
      end
      output << "…" if ellipsis
      output
    end

    def pad(text, columns)
      clipped = clip(text, columns)
      clipped + (" " * [columns - width(clipped), 0].max)
    end

    def clean(text)
      Foruiman::ANSI::Decoder.new.feed(text, eof: true).gsub(Foruiman::ANSI::SGR, "").tr("\n", " ")
    end
  end
end
