# frozen_string_literal: true

require "unicode/display_width"
require_relative "ansi"

# A single editable terminal row. Used only after a child emits a horizontal
# cursor control; ordinary append-only logs keep their fast streaming path.
class Foruiman::OutputLine
  attr_reader :cost

  def initialize(text)
    @cells = []
    @cursor = 0
    @cost = 0
    styles = Foruiman::ANSI::Styles.new
    text.scan(/\e\[[0-9;:]*m|\X/).each do |token|
      if token.match?(Foruiman::ANSI::SGR)
        styles.apply(token)
      else
        write(token, styles.prefix)
      end
    end
  end

  def write(character, style)
    width = Unicode::DisplayWidth.of(character, emoji: :all)
    if width.zero? && @cursor.positive?
      index = @cursor - 1
      index -= 1 while index.positive? && @cells[index] == :continuation
      @cells[index][0] += character if @cells[index].is_a?(Array)
    else
      width.times { |offset| clear_cell(@cursor + offset) }
      @cells[@cursor] = [character, style]
      (1...width).each { |offset| @cells[@cursor + offset] = :continuation }
      @cursor += width
    end
    # Conservative, constant-time bound including style transitions.
    @cost += character.bytesize + style.bytesize + Foruiman::ANSI::RESET.bytesize
  end

  def control(token, limit:)
    @cost = to_s.bytesize
    number = token[/\d+/].to_i
    amount = [number, 1].max
    case token
    when "\r" then @cursor = 0
    when "\b" then @cursor = [@cursor - 1, 0].max
    else
      case token[-1]
      when "G" then @cursor = (amount - 1).clamp(0, limit)
      when "C" then @cursor = (@cursor + amount).clamp(0, limit)
      when "D" then @cursor = [@cursor - amount, 0].max
      when "K" then erase(number)
      end
    end
  end

  def to_s
    style = ""
    @cells.each_with_object(+"") do |cell, text|
      next if cell == :continuation

      character, next_style = cell || [" ", ""]
      if next_style != style
        text << Foruiman::ANSI::RESET unless style.empty?
        text << next_style
        style = next_style
      end
      text << character
    end
  end

  private

  def clear_cell(index)
    if @cells[index] == :continuation
      start = index - 1
      start -= 1 while start.positive? && @cells[start] == :continuation
      @cells[start] = nil
    end
    following = index + 1
    while @cells[following] == :continuation
      @cells[following] = nil
      following += 1
    end
    @cells[index] = nil
  end

  def erase(mode)
    case mode
    when 0
      clear_cell(@cursor) if @cursor < @cells.size
      @cells.slice!(@cursor..) if @cursor < @cells.size
    when 1
      [@cursor + 1, @cells.size].min.times { |index| clear_cell(index) }
    when 2 then @cells.clear
    end
    @cost = to_s.bytesize
  end
end
