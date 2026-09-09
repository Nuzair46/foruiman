# frozen_string_literal: true

require_relative "terminal"
require_relative "state"
require_relative "keyboard"
require_relative "renderer"

module Foruiman::TUI
  class Application
    attr_reader :state

    def initialize(engine, terminal: Terminal.new, renderer: Renderer.new)
      @engine = engine
      @terminal = terminal
      @renderer = renderer
      @keyboard = Keyboard.new
      @state = State.new(engine.processes.map(&:name))
      @last_frame = nil
      @next_frame_at = 0
      @was_shutting_down = false
      @feedback_until = 0
    end

    def run
      @terminal.session do
        @engine.run(keep_open: true) do
          rows, columns = @terminal.size
          input = @terminal.read
          @engine.shutdown if input.nil?
          height = [Renderer.log_height(rows: rows, columns: columns), 1].max
          @keyboard.feed(input.is_a?(String) ? input : "").each { |key| handle(key, height) }
          state.feedback = nil if monotonic >= @feedback_until
          next if monotonic < @next_frame_at && @was_shutting_down == @engine.shutting_down?

          @was_shutting_down = @engine.shutting_down?

          @next_frame_at = monotonic + (1.0 / 30)
          frame = @renderer.render(state, @engine, rows: rows, columns: columns)
          if frame != @last_frame
            @terminal.draw(frame)
            @last_frame = frame
          end
        end
      end
    ensure
      @engine.close
    end

    def handle(key, height)
      return if @engine.shutting_down?

      if key.is_a?(Integer)
        state.select(key.zero? ? state.tabs.size - 1 : key - 1)
        return
      end
      buffer = @engine.logs[state.name]
      case key
      when :next then state.move(1)
      when :previous then state.move(-1)
      when :up then state.viewport.scroll(-1, buffer, height)
      when :down then state.viewport.scroll(1, buffer, height)
      when :page_up then state.viewport.scroll(-height, buffer, height)
      when :page_down then state.viewport.scroll(height, buffer, height)
      when :home then state.viewport.home(buffer)
      when :end, :follow then state.viewport.follow
      when :toggle_follow then state.viewport.toggle(buffer, height)
      when :help then state.help = !state.help
      when :escape then state.help = false
      when :restart, :stop then control(key)
      when :restart_all, :stop_all
        control_all(key == :restart_all ? :restart : :stop)
      when :quit then @engine.shutdown
      end
    end

    private

    def control(action)
      if state.name == "all"
        if action == :restart
          control_all(action)
        else
          feedback("Select a process first; S stops all processes")
        end
      else
        @engine.public_send(action, state.name)
        feedback("#{action == :restart ? 'Restarting' : 'Stopping'} #{state.name}")
      end
    end

    def control_all(action)
      @engine.processes.each { |entry| @engine.public_send(action, entry.name) }
      feedback("#{action == :restart ? 'Restarting' : 'Stopping'} all processes")
    end

    def feedback(message)
      state.feedback = message
      @feedback_until = monotonic + 2
    end

    def monotonic
      ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    end
  end
end
