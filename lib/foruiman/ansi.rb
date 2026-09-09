# frozen_string_literal: true

module Foruiman::ANSI
  SGR = /\e\[[0-9;:]*m/
  RESET = "\e[0m"

  # A bounded style snapshot makes each retained row independently renderable.
  class Styles
    def initialize
      @values = {}
    end

    def apply(sequence)
      values = sequence.delete_prefix("\e[").delete_suffix("m").split(";")
      values = ["0"] if values.empty?
      until values.empty?
        value = values.shift
        code = value.to_i
        case code
        when 0 then @values.clear
        when 1, 2 then @values[:intensity] = value
        when 3 then @values[:italic] = value
        when 4, 21 then @values[:underline] = value
        when 5, 6 then @values[:blink] = value
        when 7 then @values[:inverse] = value
        when 8 then @values[:conceal] = value
        when 9 then @values[:strike] = value
        when 22 then @values.delete(:intensity)
        when 23 then @values.delete(:italic)
        when 24 then @values.delete(:underline)
        when 25 then @values.delete(:blink)
        when 27 then @values.delete(:inverse)
        when 28 then @values.delete(:conceal)
        when 29 then @values.delete(:strike)
        when 30..37, 90..97 then @values[:foreground] = value
        when 40..47, 100..107 then @values[:background] = value
        when 38, 48 then color(code, value, values)
        when 39 then @values.delete(:foreground)
        when 49 then @values.delete(:background)
        end
      end
    end

    def prefix
      @values.empty? ? "" : "\e[#{@values.values.join(';')}m"
    end

    private

    def color(code, value, values)
      if value.include?(":")
        color = value
      else
        mode = values.shift
        return unless %w[2 5].include?(mode)

        count = mode == "2" ? 3 : 1
        return if values.size < count

        color = [value, mode, *values.shift(count)].join(";")
      end
      @values[code == 38 ? :foreground : :background] = color
    end
  end

  # Incremental byte parser: only text, newlines, and SGR can leave this class.
  # OSC (including clipboard), DCS, cursor controls, and other escapes are dropped.
  class Decoder
    def initialize
      @state = :text
      @escape = +""
      @pending = +"".b
    end

    def feed(bytes, eof: false)
      output = +"".b
      bytes.each_byte { |byte| consume(byte, output) }
      output = @pending + output
      @pending = +"".b
      unless eof
        length = incomplete_suffix(output)
        @pending = output.slice!(-length, length) if length.positive?
      end
      output.force_encoding(Encoding::UTF_8).scrub.delete("\u0080-\u009f")
    end

    private

    def consume(byte, output)
      case @state
      when :text
        case byte
        when 27 then @state = :escape
        when 9 then output << "    "
        when 10, 32..126, 128..255 then output << byte
        end
      when :escape
        @state = case byte
                 when 91 then :csi
                 when 93 then :osc
                 when 80, 88, 94, 95 then :string
                 when 32..47 then :intermediate
                 else :text
                 end
        @escape.clear
      when :intermediate
        @state = :text if byte >= 48
      when :csi
        if byte.between?(64, 126)
          output << "\e[#{@escape}m" if byte == 109 && @escape.match?(/\A[0-9;:]*\z/)
          @state = :text
        elsif @escape.bytesize < 96
          @escape << byte
        else
          @state = :discard_csi
        end
      when :discard_csi
        @state = :text if byte.between?(64, 126)
      when :osc, :string
        if byte == 27
          @string_state = @state
          @state = :string_escape
        elsif byte == 7 && @state == :osc
          @state = :text
        end
      when :string_escape
        @state = byte == 92 ? :text : @string_state
      end
    end

    def incomplete_suffix(bytes)
      index = bytes.bytesize - 1
      index -= 1 while index >= 0 && bytes.getbyte(index).between?(128, 191)
      return 0 if index.negative?

      lead = bytes.getbyte(index)
      expected = case lead
                 when 194..223 then 2
                 when 224..239 then 3
                 when 240..244 then 4
                 else 1
                 end
      actual = bytes.bytesize - index
      actual < expected ? actual : 0
    end
  end
end
