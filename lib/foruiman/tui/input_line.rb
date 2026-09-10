# frozen_string_literal: true

module Foruiman::TUI
  class InputLine
    # Leave room for the newline in the child's canonical terminal buffer.
    MAX_BYTES = 4095
    HISTORY_SIZE = 100
    SEQUENCES = {
      "\e[A" => :history_previous, "\e[B" => :history_next,
      "\e[C" => :right, "\e[D" => :left,
      "\e[H" => :home, "\e[F" => :end,
      "\e[1~" => :home, "\e[4~" => :end, "\e[3~" => :delete
    }.freeze
    CONTROLS = {
      1 => :home, 3 => :interrupt, 4 => :eof, 5 => :end, 8 => :backspace,
      10 => :submit, 13 => :submit, 18 => :history_previous, 21 => :clear, 23 => :delete_word,
      24 => :detach, 127 => :backspace
    }.freeze

    attr_reader :text, :cursor

    def initialize
      @text = +""
      @cursor = 0
      @bytes = +"".b
      @history = []
      @history_index = nil
      @draft = nil
    end

    def feed(bytes)
      bytes, detach, = bytes.b.partition("\x18")
      @bytes << bytes
      events = []
      until @bytes.empty?
        if @bytes.start_with?("\e")
          if @bytes.bytesize > 64 && incomplete_escape?
            @bytes.clear
            break
          end
          break if incomplete_escape?

          sequence = SEQUENCES.keys.find { |candidate| @bytes.start_with?(candidate) }
          if sequence
            edit(SEQUENCES.fetch(sequence))
            @bytes.slice!(0, sequence.bytesize)
          else
            match = @bytes.match(%r{\A\e(?:\[[0-?]*[ -/]*[@-~]|O.|.)}m)
            @bytes.slice!(0, match ? match[0].bytesize : 1)
          end
          next
        end

        byte = @bytes.getbyte(0)
        if @after_cr && byte == 10
          @bytes.slice!(0, 1)
          @after_cr = false
          next
        end
        @after_cr = byte == 13
        if CONTROLS.key?(byte)
          @bytes.slice!(0, 1)
          event = edit(CONTROLS.fetch(byte))
          events << event if event
        elsif byte < 32
          @bytes.slice!(0, 1)
        else
          character = next_character
          break unless character

          insert(character)
        end
      end
      unless detach.empty?
        @bytes.clear
        clear
        events << :detach
      end
      events
    end

    def clear
      replace("")
      @history_index = nil
      @draft = nil
    end

    private

    def edit(action)
      case action
      when :left then @cursor -= 1 if cursor.positive?
      when :right then @cursor += 1 if cursor < graphemes.size
      when :home then @cursor = 0
      when :end then @cursor = graphemes.size
      when :backspace then remove(cursor - 1) if cursor.positive?
      when :delete then remove(cursor) if cursor < graphemes.size
      when :delete_word then delete_word
      when :clear then clear
      when :history_previous then history_previous
      when :history_next then history_next
      when :submit then return submit
      when :interrupt
        clear
        return :interrupt
      when :eof
        return :eof if text.empty?

        remove(cursor) if cursor < graphemes.size
      when :detach
        clear
        return :detach
      end
      nil
    end

    def submit
      line = text.dup
      @history << line.freeze unless line.empty? || @history.last == line
      @history.shift if @history.size > HISTORY_SIZE
      clear
      [:submit, line]
    end

    def insert(character)
      return if text.bytesize + character.bytesize > MAX_BYTES
      return if character.match?(/[\u0080-\u009f]/)

      if character.ascii_only? && cursor == text.length
        @text << character
        @cursor += 1
        @history_index = nil
        return
      end

      parts = graphemes
      parts.insert(cursor, character)
      @text = parts.join
      @cursor = [cursor + 1, graphemes.size].min
      @history_index = nil
    end

    def remove(index)
      parts = graphemes
      parts.delete_at(index)
      @text = parts.join
      @cursor -= 1 if index < cursor
      @history_index = nil
    end

    def delete_word
      parts = graphemes
      index = cursor
      index -= 1 while index.positive? && parts[index - 1].match?(/\s/)
      index -= 1 while index.positive? && !parts[index - 1].match?(/\s/)
      parts.slice!(index...cursor)
      @text = parts.join
      @cursor = index
      @history_index = nil
    end

    def history_previous
      return if @history.empty?

      @draft = text.dup unless @history_index
      @history_index = [(@history_index || @history.size) - 1, 0].max
      replace(@history.fetch(@history_index))
    end

    def history_next
      return unless @history_index

      @history_index += 1
      if @history_index >= @history.size
        @history_index = nil
        replace(@draft.to_s)
        @draft = nil
      else
        replace(@history.fetch(@history_index))
      end
    end

    def replace(value)
      @text = +value
      @cursor = graphemes.size
    end

    def graphemes
      text.scan(/\X/)
    end

    def next_character
      size = utf8_size(@bytes.getbyte(0))
      return @bytes.slice!(0, 1).force_encoding(Encoding::UTF_8).scrub unless size
      unless @bytes.byteslice(1, size - 1).bytes.all? { |byte| byte.between?(128, 191) }
        return @bytes.slice!(0, 1).force_encoding(Encoding::UTF_8).scrub
      end
      return if @bytes.bytesize < size

      @bytes.slice!(0, size).force_encoding(Encoding::UTF_8).scrub
    end

    def utf8_size(byte)
      case byte
      when 0..127 then 1
      when 194..223 then 2
      when 224..239 then 3
      when 240..244 then 4
      end
    end

    def incomplete_escape?
      @bytes == "\e" || @bytes == "\e[" || @bytes == "\eO" ||
        (@bytes.start_with?("\e[") && !@bytes.match?(%r{\A\e\[[0-?]*[ -/]*[@-~]}))
    end
  end
end
