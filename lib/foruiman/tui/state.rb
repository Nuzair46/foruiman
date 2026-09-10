# frozen_string_literal: true

require_relative "viewport"

module Foruiman::TUI
  class State
    attr_reader :tabs, :selected, :viewports
    attr_accessor :help, :feedback, :input_target

    def initialize(names)
      @tabs = [*names, "all"].freeze
      @selected = tabs.size - 1
      @viewports = tabs.to_h { |name| [name, Viewport.new] }
      @help = false
      @feedback = nil
      @input_target = nil
    end

    def name
      tabs[selected]
    end

    def viewport
      viewports.fetch(name)
    end

    def input?
      !input_target.nil?
    end

    def select(index)
      @selected = index if index.between?(0, tabs.size - 1)
    end

    def move(delta)
      @selected = (selected + delta) % tabs.size
    end
  end
end
