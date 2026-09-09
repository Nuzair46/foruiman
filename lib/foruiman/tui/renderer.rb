# frozen_string_literal: true

require_relative "text"
require_relative "theme"
require_relative "log_formatter"
require "pathname"

module Foruiman::TUI
  class Renderer
    HELP = [
      ["↔ NAVIGATE", "Tab / Shift-Tab", "Change tab", "← →  or  h l"],
      [nil, "1–9 / 0", "Select a process / all logs", nil],
      ["≡ READ LOGS", "↑ ↓  or  k j", "Scroll a line", nil],
      [nil, "PgUp / PgDn", "Scroll a page", "Ctrl-U / Ctrl-D"],
      [nil, "g / Home", "Oldest retained line", nil],
      [nil, "f / G / End", "Follow newest output", nil],
      [nil, "Space", "Pause / resume following", nil],
      ["⚙ PROCESSES", "r / R", "Restart selected / all", "r on all restarts all"],
      [nil, "s / S", "Stop selected / all", nil],
      ["◇ SESSION", "? / Escape", "Close help", nil],
      [nil, "q / Ctrl-C", "Stop processes and quit", nil]
    ].freeze

    def initialize(theme: Theme.new)
      @theme = theme
      @first_tab = 0
    end

    def self.expanded?(rows:, columns:)
      rows >= 14 && columns >= 60
    end

    def self.log_height(rows:, columns:)
      return 0 if rows < 6 || columns < 24

      rows - (expanded?(rows: rows, columns: columns) ? 7 : 5)
    end

    def render(state, engine, rows:, columns:)
      @width = [columns - 1, 1].max
      @inside = [@width - 4, 0].max
      @height = self.class.log_height(rows: rows, columns: columns)
      return tiny_frame(state, engine, rows) if @height.zero?

      lines = [header(engine)]
      if self.class.expanded?(rows: rows, columns: columns)
        hint = @inside >= 70 ? " Tab switch · 1–9 / 0 select " : ""
        lines << border(@theme.paint(" processes ", :muted, bold: true), @theme.paint(hint, :faint))
        lines << panel(tab_row(state, engine, @inside - 2))
        lines << border("", "", bottom: true)
      else
        lines << " #{@theme.paint('│', :border)} #{tab_row(state, engine, @inside - 2)}"
      end
      lines << log_header(state, engine)
      lines.concat(state.help ? help_rows : log_rows(state, engine))
      lines << log_footer(state, engine)
      lines << controls(state, engine)
      frame(lines, rows)
    end

    def self.width(text)
      Text.width(text)
    end

    def self.truncate(text, columns)
      Text.clip(text, columns) + Foruiman::ANSI::RESET
    end

    private

    def header(engine)
      brand = @width >= 45 ? "▰ FORUIMAN" : "▰"
      left = " #{@theme.paint(brand, :accent, bold: true)}"
      right = if engine.shutting_down?
                @theme.paint("◌ shutting down", :amber)
              elsif @width >= 60
                summary(engine)
              else
                ""
              end
      source = if engine.procfile_path
                 Text.clean(Pathname.new(engine.procfile_path).relative_path_from(Pathname.new(engine.root)).to_s)
               end
      project = @theme.paint("  / #{Text.clean(File.basename(engine.root))}", :muted)
      left += project if @width >= 70 && Text.width(left + project + source.to_s + right) + 5 <= @width
      if source
        available = [@width - Text.width(left + right) - 4, 0].max
        source = "…/#{File.basename(source)}" if Text.width(source) > available && source.include?("/")
        left += @theme.paint("  #{Text.clip(source, available, ellipsis: true)}")
      end
      distribute(left, "#{right} ", @width)
    end

    def summary(engine)
      running = engine.processes.count { |entry| entry.status == :running }
      failed = engine.processes.count { |entry| entry.status == :failed }
      summary = @theme.paint("● #{running} running", running.positive? ? :green : :muted)
      summary += @theme.paint("  × #{failed} failed", :red) if failed.positive? && @width >= 55
      summary
    end

    def tab_row(state, engine, width)
      @first_tab = state.selected if state.selected < @first_tab
      labels = state.tabs.each_with_index.map { |name, index| tab(name, index, state, engine, width) }
      @first_tab += 1 while @first_tab < state.selected && tab_span(labels, @first_tab, state.selected) > width
      output = +(@first_tab.positive? ? @theme.paint("‹ ", :muted) : "")
      index = @first_tab
      while index < labels.size
        separator = index == @first_tab ? "" : " "
        more = index < labels.size - 1 ? 2 : 0
        available = width - Text.width(output) - more - separator.size
        break if Text.width(labels[index]) > available && index > @first_tab

        output << separator << Text.clip(labels[index], [available, 0].max) << @theme.reset
        index += 1
      end
      output << @theme.paint(" ›", :muted) if index < labels.size
      Text.clip(output, width)
    end

    def tab_span(labels, first, last)
      Text.width(labels[first..last].join(" ")) + (first.positive? ? 2 : 0) + (last < labels.size - 1 ? 2 : 0)
    end

    def tab(name, index, state, engine, width)
      selected = index == state.selected
      entry = name == "all" ? nil : engine.processes.find { |process| process.name == name }
      mark = name == "all" ? "≡" : Theme::STATUS_MARKS.fetch(entry&.status, "○")
      number = if name == "all"
                 "0"
               else
                 (index < 9 ? (index + 1).to_s : "·")
               end
      name = Text.clip(name, [width - 12, 6].max.clamp(6, 22), ellipsis: true)
      color = name == "all" ? :accent : @theme.process(index)
      mark_color = entry ? Theme::STATUS_COLORS.fetch(entry.status, :muted) : :muted
      @theme.paint(" #{number} ", selected ? :muted : :faint, selected: selected) +
        @theme.paint("#{mark} ", mark_color, selected: selected) +
        @theme.paint("#{name} ", color, selected: selected, bold: selected)
    end

    def log_header(state, engine)
      if state.help
        return border(@theme.paint(" ⌨ keyboard shortcuts ", :text, bold: true),
                      @theme.paint(" ? / Escape close help ", :muted))
      end

      title = state.name == "all" ? " ≡ all logs " : " › #{state.name} "
      detail = if state.name == "all"
                 "#{engine.processes.size} processes"
               else
                 entry = engine.state(state.name)
                 process_detail(entry)
               end
      active = if state.name == "all"
                 engine.processes.any? { |entry| entry.status == :running }
               else
                 engine.state(state.name).status == :running
               end
      mode = if !state.viewport.following
               @theme.paint(" Ⅱ PAUSED ", :amber)
             elsif active
               @theme.paint(" ● LIVE ", :green)
             else
               @theme.paint(" ↓ FOLLOW ", :muted)
             end
      title = @theme.paint(title, :text, bold: true)
      if @inside >= 45
        title += @theme.paint(" #{detail} ", :muted)
      elsif state.name != "all" && @inside >= 28
        entry = engine.state(state.name)
        title += @theme.paint(" #{entry.status} ", Theme::STATUS_COLORS.fetch(entry.status, :muted))
      end
      border(title, mode)
    end

    def process_detail(entry)
      detail = "#{entry.status} · PID #{entry.pid || '-'}"
      if entry.exit_status
        code = entry.exit_status.exitstatus || "signal #{entry.exit_status.termsig}"
        detail += " · exit #{code}"
      elsif entry.port && @inside >= 75
        detail += " · PORT #{entry.port}"
      end
      detail
    end

    def log_rows(state, engine)
      @formatter ||= LogFormatter.new(@theme, engine.process_names)
      buffer = engine.logs[state.name]
      records = state.viewport.rows(buffer, @height)
      @visible = records
      first = records.empty? ? 0 : buffer.index_of(records.first.sequence).to_i
      thumb_size = buffer.none? ? @height : [(@height * @height / buffer.size), 1].max.clamp(1, @height)
      travel = @height - thumb_size
      thumb_start = buffer.size <= @height ? 0 : (first * travel / (buffer.size - @height))
      Array.new(@height) do |index|
        content = if records[index]
                    @formatter.row(records[index], aggregate: state.name == "all", width: @inside - 2)
                  elsif records.empty? && index == @height / 2
                    @theme.paint("Waiting for output…", :faint)
                  else
                    ""
                  end
        thumb = buffer.size > @height && index.between?(thumb_start, thumb_start + thumb_size - 1)
        panel(content, scroll: if thumb
                                 state.viewport.following ? :green : :amber
                               end)
      end
    end

    def log_footer(state, engine)
      return border("", "", bottom: true) if state.help

      buffer = engine.logs[state.name]
      first = @visible&.first
      last = @visible&.last
      range = first ? "#{buffer.index_of(first.sequence) + 1}–#{buffer.index_of(last.sequence) + 1}" : "0"
      count = " #{range} / #{buffer.size} lines "
      location = if state.viewport.following
                   " following "
                 else
                   " f resume "
                 end
      location = " PID #{engine.state(state.name).pid || '-'} " if state.name != "all" && @inside < 45
      border(@theme.paint(count, :faint), @theme.paint(location, state.viewport.following ? :faint : :amber),
             bottom: true)
    end

    def help_rows
      rows = []
      HELP.each do |section, key, description, alias_keys|
        if section && @height >= 15
          rows << panel("") if !rows.empty? && @height >= 18
          rows << panel(@theme.paint(section, :accent, bold: true))
        end
        line = @theme.paint(Text.pad(key, 18), :amber, bold: true) + @theme.paint(description)
        line += @theme.paint("  #{alias_keys}", :faint) if alias_keys && @inside >= 75
        rows << panel(line)
      end
      rows = rows.first(@height)
      rows << panel("") while rows.size < @height
      rows
    end

    def controls(state, engine)
      quit = @theme.paint(" q ", :accent, bold: true) + @theme.paint(" × quit ", :muted)
      left = if engine.shutting_down?
               @theme.paint(" ◌ Stopping process groups · TERM → KILL after 5s", :amber)
             elsif state.feedback
               @theme.paint(" #{state.feedback}", :amber)
             elsif state.help
               @theme.paint(" ? / Escape close help", :muted)
             else
               shortcuts(state)
             end
      distribute(left, quit, @width)
    end

    def shortcuts(state)
      restart = ["r", state.name == "all" ? "↻ restart all" : "↻ restart"]
      pairs = [%w[Tab switch], ["↑↓", "scroll"], %w[f follow], restart, ["?", "help"]]
      pairs = [restart, ["?", "help"]] if @width < 65
      pairs.map do |key, label|
        @theme.paint(" #{key} ", :accent, bold: true) + @theme.paint(" #{label}  ", :muted)
      end.join
    end

    def border(left, right = "", bottom: false)
      corners = bottom ? %w[╰ ╯] : %w[╭ ╮]
      middle = distribute(left, right, @inside, fill: "─")
      " #{@theme.paint(corners.first, :border)}#{@theme.paint(middle, :border)}#{@theme.paint(corners.last, :border)} "
    end

    def panel(content, scroll: nil)
      inside = Text.pad(Text.clip(content, @inside - 2), @inside - 2)
      edge = @theme.paint(scroll ? "┃" : "│", scroll || :border)
      " #{@theme.paint('│', :border)} #{inside}#{@theme.reset} #{edge} "
    end

    def distribute(left, right, width, fill: " ")
      right = Text.clip(right, [width / 2, Text.width(right)].min)
      available = [width - Text.width(right), 0].max
      left = Text.clip(left, available, ellipsis: true)
      gap = [width - Text.width(left) - Text.width(right), 0].max
      left + @theme.reset + @theme.paint(fill * gap, :border) + right + @theme.reset
    end

    def tiny_frame(state, engine, rows)
      title = @theme.paint(" FORUIMAN", :accent, bold: true)
      message = engine.shutting_down? ? " Stopping…" : " #{state.name} · enlarge terminal"
      lines = [title, @theme.paint(message, :muted)]
      lines[rows - 1] = @theme.paint(" q quit", :accent) if rows > 2
      frame(lines, rows)
    end

    def frame(lines, rows)
      rendered = Array.new(rows) do |index|
        # Erase before drawing, then restore the theme defaults. Reserve the last
        # cell to avoid terminal autowrap.
        "\e[2K#{@theme.base}#{self.class.truncate(lines[index].to_s, @width)}"
      end.join("\r\n")
      "\e[H#{rendered}"
    end
  end
end
