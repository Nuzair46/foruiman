# frozen_string_literal: true

require_relative "../ansi"

module Foruiman::TUI
  # Use the terminal's palette and default background, so its theme owns the
  # actual colors (and can change them while Foruiman is running).
  class Theme
    COLORS = {
      text: 39, muted: 90, faint: 90, border: 90, accent: 36,
      green: 32, red: 31, amber: 33, cyan: 36, blue: 34, mauve: 35
    }.freeze
    PROCESS_COLORS = %i[cyan amber mauve green blue red].freeze
    STATUS_COLORS = {
      pending: :faint, running: :green, restarting: :amber, stopping: :amber,
      stopped: :muted, exited: :muted, failed: :red
    }.freeze
    STATUS_MARKS = {
      pending: "○", running: "▶", restarting: "↻", stopping: "◼",
      stopped: "■", exited: "✓", failed: "✕"
    }.freeze

    attr_reader :enabled

    def initialize(env: ENV)
      @enabled = env.fetch("NO_COLOR", "").empty? && env["TERM"] != "dumb"
    end

    def base
      enabled ? "\e[39m\e[49m" : ""
    end

    def paint(text, color = :text, selected: false, bold: false)
      emphasis = "#{"\e[7m" if selected}#{"\e[1m" if bold}"
      return emphasis.empty? ? text : "#{emphasis}#{text}#{reset}" unless enabled

      defaults = selected ? base : "#{code(color)}\e[49m"
      "#{defaults}#{emphasis}#{text}#{reset}"
    end

    def reset
      enabled ? Foruiman::ANSI::RESET + base : Foruiman::ANSI::RESET
    end

    def process(index)
      PROCESS_COLORS[index % PROCESS_COLORS.size]
    end

    # A child reset restores the UI's defaults. Explicit child colors, including
    # background colors, still win; they cannot bleed into borders or later rows.
    def log(text, color: :text)
      return text.gsub(Foruiman::ANSI::SGR, "") unless enabled

      defaults = "#{code(color)}\e[49m"
      styles = Foruiman::ANSI::Styles.new
      content = text.gsub(Foruiman::ANSI::SGR) do |sequence|
        styles.apply(sequence)
        Foruiman::ANSI::RESET + defaults + styles.prefix
      end
      defaults + content + reset
    end

    private

    def code(color)
      return "" unless enabled

      "\e[#{COLORS.fetch(color)}m"
    end
  end
end
