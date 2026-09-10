# frozen_string_literal: true

require_relative "process"
require_relative "log_store"
require_relative "output"

# Derived from Foreman's registration, process lookup, pipes and self-pipe signal
# handling. All process state and output now belong to the caller's event loop.
class Foruiman::Engine
  HANDLED_SIGNALS = %i[INT TERM HUP].freeze
  TERM_TIMEOUT = 5.0
  READ_CHUNK = 4096
  READ_BUDGET = 64 * 1024
  INPUT_BUDGET = 64 * 1024
  State = Struct.new(:name, :process, :port, :pid, :pgid, :status, :exit_status,
                     :generation, :restart_pending, :deadline, :reaped, :group_gone,
                     :enabled, :input, :input_buffer,
                     keyword_init: true)
  Event = Data.define(:type, :name, :pid, :status, :record, :message)

  attr_reader :logs, :env, :processes, :root, :procfile_path

  def initialize(procfile: nil, root: Dir.pwd, env: ENV.to_h, input: $stdin, port: 5000, log_lines: 10_000,
                 term_timeout: TERM_TIMEOUT)
    raise Foruiman::Error, "port must be an integer in 1..65535" unless port.is_a?(Integer) && (1..65_535).cover?(port)
    raise Foruiman::Error, "log-lines must be a positive integer" unless log_lines.is_a?(Integer) && log_lines.positive?

    @root = File.expand_path(root)
    raise Foruiman::Error, "working directory does not exist: #{@root}" unless File.directory?(@root)

    @env = env.dup.freeze
    @input = input
    @managed_input = false
    @base_port = port
    @log_lines = log_lines
    @term_timeout = term_timeout
    @processes = []
    @names = {}
    @running = {}
    @readers = {}
    @inputs = {}
    @listeners = []
    @shutdown = false
    @explicit_shutdown = false
    @failed = false
    @closed = false
    @started = false
    @signal_requested = false
    @self_reader, @self_writer = create_pipe
    load_procfile(procfile) if procfile
  rescue StandardError
    @self_reader&.close
    @self_writer&.close
    raise
  end

  def register(name, command)
    raise Foruiman::Error, "cannot register after startup" if @started
    raise Foruiman::Error, "duplicate process: #{name}" if @names.key?(name)
    raise Foruiman::Error, "allocated port exceeds 65535 for #{name}" if @base_port + (processes.size * 100) > 65_535

    Foruiman::Procfile.new[name] = command
    process = Foruiman::Process.new(command, cwd: root, env: env)
    state = State.new(name: name.freeze, process: process, port: @base_port + (processes.size * 100),
                      status: :pending, generation: 0, restart_pending: false, reaped: true, group_gone: true,
                      enabled: true, input_buffer: +"".b)
    @names[name] = state
    processes << state
    state
  end

  def load_procfile(filename)
    parsed = Foruiman::Procfile.new(filename)
    entries = parsed.entries.to_a
    last_port = @base_port + ((processes.size + entries.size - 1) * 100)
    raise Foruiman::Error, "allocated port #{last_port} exceeds 65535" if last_port > 65_535

    entries.each { |name, command| register(name, command) }
    @procfile_path = File.expand_path(filename).freeze
    self
  end

  def process_names
    @names.keys
  end

  def process(name)
    @names[name]&.process
  end

  def state(name)
    @names.fetch(name)
  end

  def select(name)
    raise Foruiman::Error, "cannot select after startup" if @started
    raise Foruiman::Error, "unknown process: #{name}" unless @names.key?(name)

    @names.select! { |key, _entry| key == name }
    processes.select! { |entry| entry.name == name }
    self
  end

  def on_event(&listener)
    @listeners << listener
    self
  end

  # Give every child a dedicated pseudo-terminal for stdin. The TUI remains the
  # sole reader of the real terminal and explicitly forwards input to one child.
  def manage_input!
    raise Foruiman::Error, "cannot change input mode after startup" if @started

    require "pty"
    @managed_input = true
    self
  end

  def start(name = nil)
    raise Foruiman::Error, "supervisor is closed" if @closed
    return if @shutdown

    targets = name ? [state(name)] : processes
    unless @started
      @logs = Foruiman::LogStore.new(process_names, capacity: @log_lines) do |record|
        emit(:output, state(record.name), record: record)
      end
      @started = true
    end
    targets.each { |entry| spawn_process(entry) if entry.enabled && !entry.pgid }
    self
  end

  alias start_all start

  def restart(name)
    return if @shutdown || @closed

    return start(name) unless @started

    entry = state(name)
    return unless entry.enabled
    return if entry.restart_pending

    entry.restart_pending = true
    entry.status = :restarting
    lifecycle(entry, :restarting, "restarting")
    if entry.pgid
      terminate(entry)
    else
      spawn_process(entry)
    end
  end

  def stop(name)
    entry = state(name)
    entry.restart_pending = false
    return unless entry.pgid

    entry.status = :stopping
    lifecycle(entry, :stopping, "stopping")
    terminate(entry)
  end

  def disable(name)
    return if @shutdown || @closed

    entry = state(name)
    return unless entry.enabled

    entry.enabled = false
    entry.restart_pending = false
    if entry.pgid
      entry.status = :disabling
      lifecycle(entry, :disabling, "disabling")
      terminate(entry)
    else
      entry.status = :disabled
      lifecycle(entry, :disabled, "disabled")
    end
    self
  end

  def enable(name)
    return if @shutdown || @closed

    entry = state(name)
    return if entry.enabled

    entry.enabled = true
    lifecycle(entry, :enabled, "enabled")
    if entry.pgid
      entry.restart_pending = true
      entry.status = :restarting
    elsif @started
      spawn_process(entry)
    else
      entry.status = :pending
    end
    self
  end

  def write_input(name, bytes)
    entry = state(name)
    return false unless entry.status == :running && entry.input && !entry.input.closed?
    return false if entry.input_buffer.bytesize + bytes.bytesize > INPUT_BUDGET

    entry.input_buffer << bytes.b
    flush_input(entry)
  rescue IOError, SystemCallError
    false
  end

  def interrupt_process(name)
    entry = state(name)
    return unless entry.pgid

    signal_group(entry, :INT)
    self
  end

  def resize_inputs(rows, columns)
    processes.each do |entry|
      entry.input&.winsize = [rows, columns]
    rescue IOError, SystemCallError
      nil
    end
  end

  def shutdown(explicit: true)
    @explicit_shutdown ||= explicit
    return if @shutdown

    @shutdown = true
    processes.each do |entry|
      entry.restart_pending = false
      stop(entry.name)
    end
  end

  def shutting_down?
    @shutdown
  end

  def finished?
    @started && processes.all? { |entry| !entry.pgid && !entry.restart_pending } && @readers.empty?
  end

  def exit_code
    @explicit_shutdown || !@failed ? 0 : 1
  end

  def run(keep_open: false)
    register_signal_handlers
    start_all
    loop do
      tick(timeout: keep_open ? 1.0 / 30 : 0.05)
      yield self if block_given?
      break if finished? && (!keep_open || shutting_down?)
    end
    exit_code
  ensure
    close
  end

  # Embedders may drive this method directly; start/restart/stop are called on
  # that same thread. A bounded round-robin read prevents output starving input.
  def tick(timeout: 0.03)
    return if @closed

    shutdown if @signal_requested
    reap_children
    advance_groups
    writable = processes.filter_map { |entry| entry.input unless entry.input_buffer.empty? }
    ready, writable = IO.select([@self_reader, *@readers.keys], writable, nil, timeout) || [[], []]
    drain_signal_pipe if ready.delete(@self_reader)
    shutdown if @signal_requested
    writable.each { |input| flush_input(@inputs.fetch(input)) if @inputs.key?(input) }
    read_output(ready)
    reap_children
    advance_groups
  rescue Errno::EINTR
    # The next tick handles the deferred signal.
  end

  def close
    return if @closed

    # Observers can fail (e.g. a closed stdout). Cleanup must still own the loop.
    @listeners.clear
    shutdown(explicit: false)
    tick(timeout: 0.01) until !@started || finished?
  ensure
    restore_signal_handlers
    @self_reader.close unless @self_reader.closed?
    @self_writer.close unless @self_writer.closed?
    @closed = true
  end

  private

  def create_pipe
    IO.pipe("BINARY").each { |io| io.close_on_exec = true }
  end

  def spawn_process(entry)
    return if @shutdown

    stdout_reader, stdout_writer = create_pipe
    stderr_reader, stderr_writer = create_pipe
    input_master, input_slave = create_managed_input if @managed_input
    begin
      pid = entry.process.run(output: stdout_writer, error: stderr_writer,
                              input: input_slave || @input,
                              env: { "PORT" => entry.port.to_s, "PS" => "#{entry.name}.1" })
    rescue SystemCallError => e
      stdout_reader.close
      stderr_reader.close
      input_master&.close
      entry.status = :failed
      entry.restart_pending = false
      @failed = true
      lifecycle(entry, :failed, "failed to start: #{e.message}")
      return
    end
    entry.pid = entry.pgid = pid
    entry.status = :running
    entry.exit_status = nil
    entry.generation += 1
    entry.restart_pending = false
    entry.deadline = nil
    entry.reaped = entry.group_gone = false
    entry.input = input_master
    entry.input_buffer.clear
    @running[pid] = entry
    [[stdout_reader, :stdout], [stderr_reader, :stderr]].each do |reader, stream|
      @readers[reader] = [entry, Foruiman::Output.new(logs, name: entry.name, stream: stream, pid: pid)]
    end
    if input_master
      @inputs[input_master] = entry
      @readers[input_master] = [entry, Foruiman::Output.new(logs, name: entry.name, stream: :stdin, pid: pid)]
    end
    lifecycle(entry, :started, "started with pid #{pid} (generation #{entry.generation})")
  ensure
    input_slave&.close
    stdout_writer&.close
    stderr_writer&.close
    [stdout_reader, stderr_reader].compact.each do |reader|
      reader.close unless reader.closed? || @readers.key?(reader)
    end
  end

  def terminate(entry)
    return if entry.deadline || entry.group_gone

    signal_group(entry, :TERM)
    entry.deadline = monotonic + @term_timeout
  end

  def signal_group(entry, signal)
    ::Process.kill(signal, -entry.pgid) if entry.pgid
  rescue Errno::ESRCH
    entry.group_gone = true
  end

  def reap_children
    @running.keys.each do |pid| # rubocop:disable Style/HashEachMethods -- observers can add processes
      result = ::Process.waitpid2(pid, ::Process::WNOHANG)
      next unless result

      entry = @running.delete(pid)
      entry.reaped = true
      entry.exit_status = result.last
      success = entry.exit_status.success?
      transitioning = %i[stopping restarting disabling].include?(entry.status)
      @failed ||= !success && !transitioning
      entry.status = success ? :exited : :failed unless transitioning
      lifecycle(entry, :exited, termination_message_for(entry.exit_status))
      terminate(entry)
    end
  end

  def advance_groups
    processes.each do |entry|
      next unless entry.pgid
      next unless entry.reaped || entry.deadline

      entry.group_gone ||= !group_alive?(entry.pgid)
      if !entry.group_gone && entry.deadline && monotonic >= entry.deadline
        signal_group(entry, :KILL)
        lifecycle(entry, :killed, "sent SIGKILL after TERM timeout")
        entry.deadline = nil
      end
      next unless entry.reaped && entry.group_gone
      next if @readers.any? { |_reader, (owner, _output)| owner.equal?(entry) }

      close_input(entry)
      entry.pgid = nil
      entry.deadline = nil
      entry.status = entry.enabled ? :stopped : :disabled if %i[stopping disabling].include?(entry.status)
      spawn_process(entry) if entry.restart_pending && !@shutdown
    end
  end

  def group_alive?(pgid)
    ::Process.kill(0, -pgid)
    return true unless RUBY_PLATFORM.include?("linux")

    # Linux containers may leave orphan zombies unreaped under PID 1. They
    # cannot run or receive signals, and must not hold shutdown open forever.
    Dir.glob("/proc/[0-9]*/stat").any? do |filename|
      fields = File.read(filename).rpartition(") ").last.split
      fields[2].to_i == pgid && !%w[Z X].include?(fields[0])
    rescue Errno::ENOENT, Errno::ESRCH, Errno::EACCES
      false
    end
  rescue Errno::ESRCH
    false
  end

  def read_output(ready)
    budget = READ_BUDGET
    ready.each do |reader|
      break if budget <= 0

      entry, output = @readers.fetch(reader)
      begin
        bytes = reader.read_nonblock(READ_CHUNK, exception: false)
        if bytes.nil? || (bytes == :wait_readable && entry.group_gone)
          finish_reader(reader, entry, output)
        elsif bytes != :wait_readable
          budget -= bytes.bytesize
          output.feed(bytes)
          # Rotate serviced readers to the back for the next select.
          @readers[reader] = @readers.delete(reader)
        end
      rescue Errno::EIO
        # PTY masters report EIO when the child closes the slave side.
        finish_reader(reader, entry, output)
      end
    end
    # A daemon that escaped the group may still hold a pipe open. Drain available
    # bytes, but do not wait on it once every owned group member has finished.
    @readers.keys.each do |reader| # rubocop:disable Style/HashEachMethods -- observers can add readers
      entry, output = @readers.fetch(reader)
      next unless entry.group_gone && !ready.include?(reader)

      finish_reader(reader, entry, output)
    end
  end

  def create_managed_input
    master, slave = PTY.open
    [master, slave].each do |io|
      io.binmode
      io.close_on_exec = true
    end
    [master, slave]
  end

  def flush_input(entry)
    return if entry.input_buffer.empty? || !entry.input

    written = entry.input.write_nonblock(entry.input_buffer, exception: false)
    entry.input_buffer.slice!(0, written) if written.is_a?(Integer)
    true
  rescue IOError, SystemCallError
    reader = entry.input
    finish_reader(reader, entry, @readers.fetch(reader).last) if reader && @readers.key?(reader)
    false
  end

  def finish_reader(reader, entry, output)
    @readers.delete(reader)
    @inputs.delete(reader)
    entry.input = nil if entry.input.equal?(reader)
    reader.close unless reader.closed?
    output.feed("", eof: true)
  end

  def close_input(entry)
    input = entry.input
    return unless input

    @inputs.delete(input)
    @readers.delete(input)
    input.close unless input.closed?
    entry.input = nil
    entry.input_buffer.clear
  end

  def lifecycle(entry, type, message)
    logs&.write(name: entry.name, stream: :lifecycle, pid: entry.pid,
                text: "--- #{message} ---", complete: true)
    emit(type, entry, message: message)
  end

  def emit(type, entry, record: nil, message: nil)
    event = Event.new(type: type, name: entry.name, pid: entry.pid, status: entry.status,
                      record: record, message: message&.freeze)
    @listeners.each { |listener| listener.call(event) }
  end

  def termination_message_for(status)
    if status.exited?
      "exited with code #{status.exitstatus}"
    else
      "terminated by SIG#{Signal.list.key(status.termsig)}"
    end
  end

  def register_signal_handlers
    @old_handlers = {}
    HANDLED_SIGNALS.each do |signal|
      @old_handlers[signal] = Signal.trap(signal) do
        @signal_requested = true
        notice_signal
      end
    end
  end

  def restore_signal_handlers
    @old_handlers&.each { |signal, handler| Signal.trap(signal, handler) }
    @old_handlers = nil
  end

  def notice_signal
    @self_writer.write_nonblock(".", exception: false)
  rescue Errno::EINTR
    retry
  end

  def drain_signal_pipe
    @self_reader.read_nonblock(4096, exception: false)
  end

  def monotonic
    ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
  end
end
