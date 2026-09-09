# frozen_string_literal: true

module Foruiman::TUI
  class Viewport
    attr_reader :following, :anchor

    def initialize
      @following = true
      @anchor = nil
    end

    def rows(buffer, height)
      height = [height, 0].max
      start = top(buffer, height)
      Array.new([height, buffer.size - start].min) { |offset| buffer[start + offset] }
    end

    def scroll(delta, buffer, height)
      index = top(buffer, height)
      @following = false
      set_anchor(index + delta, buffer, height)
    end

    def home(buffer)
      @following = false
      @anchor = buffer[0]&.sequence
    end

    def follow
      @following = true
      @anchor = nil
    end

    def toggle(buffer, height)
      following ? scroll(0, buffer, height) : follow
    end

    private

    def top(buffer, height)
      last = [buffer.size - height, 0].max
      return last if following

      index = buffer.index_of(anchor) || 0
      index = [index, last].min
      @anchor = buffer[index]&.sequence
      index
    end

    def set_anchor(index, buffer, height)
      last = [buffer.size - height, 0].max
      index = index.clamp(0, last)
      @anchor = buffer[index]&.sequence
    end
  end
end
