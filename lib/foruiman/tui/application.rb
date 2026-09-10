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
      @engine.manage_input!
      @terminal.session do
        @engine.run(keep_open: true) do
          rows, columns = @terminal.size
          @engine.resize_inputs(rows, columns)
          detach_unavailable_input
          input = @terminal.read
          @engine.shutdown if input.nil?
          height = [Renderer.log_height(rows: rows, columns: columns, input: state.input?), 1].max
          read_keys(input.is_a?(String) ? input : "", height)
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
      when :restart then control(key)
      when :stop then toggle_process
      when :input then begin_input
      when :restart_all, :stop_all
        control_all(key == :restart_all ? :restart : :stop)
      when :quit then @engine.shutdown
      end
    end

    private

    def read_keys(bytes, height)
      @keyboard.feed("").each { |key| handle(key, height) } unless state.input?
      bytes.bytes.each_with_index do |byte, index|
        if state.input?
          forward_input(bytes.byteslice(index..))
          break
        end
        @keyboard.feed(byte.chr).each { |key| handle(key, height) }
      end
    end

    def begin_input
      if state.name == "all"
        feedback("Select a process before entering input mode")
      elsif @engine.state(state.name).status != :running
        feedback("#{state.name} is not running")
      else
        state.help = false
        state.viewport.follow
        state.input_target = state.name
        state.feedback = nil
      end
    end

    def forward_input(bytes)
      name = state.input_target
      state.input_line.feed(bytes).each do |event|
        case event
        when :detach
          state.input_target = nil
          feedback("Returned from #{name}")
        when :interrupt then @engine.interrupt_process(name)
        when :eof then send_input(name, "\x04")
        when Array then send_input(name, "#{event.last}\n")
        end
      end
    end

    def send_input(name, bytes)
      return if @engine.write_input(name, bytes)

      state.input_target = nil
      feedback("Input unavailable for #{name}")
    end

    def detach_unavailable_input
      return unless state.input?
      return if @engine.state(state.input_target).status == :running

      name = state.input_target
      state.input_target = nil
      feedback("Input closed for #{name}")
    end

    def toggle_process
      if state.name == "all"
        control_all(:stop)
        return
      end

      entry = @engine.state(state.name)
      if entry.pgid
        @engine.stop(state.name)
        feedback("Stopping #{state.name}")
      else
        @engine.start(state.name)
        feedback("Starting #{state.name}")
      end
    end

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
