# frozen_string_literal: true

require_relative "ansi"

class Foruiman::Output
  MAX_BYTES = 16 * 1024

  def initialize(logs, name:, stream:, pid:)
    @logs = logs
    @metadata = { name: name, stream: stream, pid: pid }
    @decoder = Foruiman::ANSI::Decoder.new
    @styles = Foruiman::ANSI::Styles.new
    @text = +""
    @previous = nil
    @dirty = false
    @split_boundary = false
  end

  def feed(bytes, eof: false)
    decoded = @decoder.feed(bytes, eof: eof)
    decoded.scan(/\e\[[0-9;:]*m|\n|[^\e\n]+/).each do |token|
      if token == "\n"
        if @split_boundary && !@dirty && !@previous
          @split_boundary = false
        else
          publish(true)
        end
      elsif token.start_with?("\e[")
        split_record if @text.bytesize + token.bytesize > MAX_BYTES
        @text << token
        @styles.apply(token)
        @dirty = true
      else
        append_text(token)
      end
    end
    if eof
      publish(true) if @dirty || @previous
    elsif @dirty
      publish(false)
    end
  end

  private

  def append_text(text)
    until text.empty?
      available = MAX_BYTES - @text.bytesize
      piece = text.byteslice(0, available)
      piece = piece.byteslice(0, piece.bytesize - 1) until piece.valid_encoding?
      if piece.empty?
        split_record
        next
      end
      @text << piece
      @dirty = true
      text = text.byteslice(piece.bytesize..)
      split_record if @text.bytesize == MAX_BYTES
    end
  end

  def split_record
    publish(true)
    @split_boundary = true
  end

  def publish(complete)
    @split_boundary = false
    @previous = @logs.write(**@metadata, text: @text, complete: complete, previous: @previous)
    @dirty = false
    return unless complete

    @text = +@styles.prefix
    @previous = nil
  end
end
