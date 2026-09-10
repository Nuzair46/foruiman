# frozen_string_literal: true

require_relative "text"
require_relative "theme"

module Foruiman::TUI
  class LogFormatter
    def initialize(theme, names)
      @theme = theme
      @colors = names.each_with_index.to_h { |name, index| [name, theme.process(index)] }
      @name_width = names.map { |name| Text.width(name) }.max.to_i.clamp(3, 14)
    end

    def row(record, aggregate:, width:)
      prefix = +""
      prefix << @theme.paint("#{record.time.strftime('%H:%M:%S')}  ", :faint) if width >= 55
      if aggregate
        name_width = [@name_width, width / 5].min
        name = Text.pad(Text.clip(record.name, name_width, ellipsis: true), name_width)
        prefix << @theme.paint(name, @colors.fetch(record.name, :cyan)) << "  "
      end
      marker, color = stream_style(record.stream)
      prefix << @theme.paint(marker, color) << @theme.paint(" │ ", :border)
      content = record.stream == :lifecycle ? record.text.delete_prefix("--- ").delete_suffix(" ---") : record.text
      content = Text.clip(content, [width - Text.width(prefix), 0].max, ellipsis: true)
      prefix + @theme.log(content, color: body_color(record.stream))
    end

    private

    def stream_style(stream)
      case stream
      when :stdin then ["in ", :cyan]
      when :stderr then ["err", :red]
      when :lifecycle then ["sys", :amber]
      else ["out", :faint]
      end
    end

    def body_color(stream)
      case stream
      when :stdin then :cyan
      when :stderr then :red
      when :lifecycle then :muted
      else :text
      end
    end
  end
end
