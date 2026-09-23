# frozen_string_literal: true

require "pty"
require "io/console"
require "foruiman/tui/terminal"

RSpec.describe "PTY and signal integration" do
  def with_terminal(*command)
    master, slave = PTY.open
    slave.winsize = [16, 90]
    original = slave.console_mode
    original_mode = IO.popen(["stty", "-g"], in: slave, &:read)
    colors = { "NO_COLOR" => nil, "TERM" => "xterm-256color", "COLORTERM" => "truecolor" }
    pid = Process.spawn(colors, *command, in: slave, out: slave, err: slave, chdir: @directory, pgroup: true)
    output = +""
    yield master, slave, pid, output
    eventually(timeout: 10) do
      chunk = master.read_nonblock(65_536, exception: false)
      output << chunk if chunk.is_a?(String)
      !alive?(pid) && !chunk.is_a?(String)
    rescue Errno::EIO
      !alive?(pid)
    end
    _pid, status = Process.waitpid2(pid)
    expect(IO.popen(["stty", "-g"], in: slave, &:read)).to eq(original_mode)
    members = Dir.glob(File.join(@directory, "*.pids")).flat_map { |file| File.read(file).split.map(&:to_i) }
    expect(members.select { |member| alive?(member) }).to be_empty
    expect(output).to include(Foruiman::TUI::Terminal::LEAVE, "\e[39m", "\e[49m", "\e[36m", "\e[7m")
    status
  ensure
    if pid
      begin
        Process.kill(:KILL, -pid)
      rescue Errno::ESRCH
        nil
      end
      begin
        Process.waitpid(pid)
      rescue Errno::ECHILD
        nil
      end
    end
    slave.console_mode = original if slave && !slave.closed? && original
    master&.close
    slave&.close
    # Every fixture writes group members before announcing readiness. Tests must
    # clean them even when an assertion above fails or the supervisor crashes.
    Dir.glob(File.join(@directory, "*.pids")).each do |filename|
      File.read(filename).split.map(&:to_i).each do |child|
        Process.kill(:KILL, child) if alive?(child)
      rescue Errno::ESRCH
        nil
      end
    end
  end

  def command(*args)
    [RbConfig.ruby, "-I", File.expand_path("../../lib", __dir__),
     File.expand_path("../../bin/foruiman", __dir__), *args]
  end

  def read_until(master, output, text, timeout: 5)
    eventually(timeout: timeout) do
      bytes = master.read_nonblock(65_536, exception: false)
      output << bytes if bytes.is_a?(String)
      output.include?(text)
    end
  end

  it "accepts keyboard input and resizing, keeps exited logs open, and restores the terminal" do
    write_file("Procfile", "web: #{fixture('partial')}\n")
    status = with_terminal(*command) do |master, slave, pid, output|
      read_until(master, output, "partial")
      expect(output).to include("Procfile")
      read_until(master, output, "exited with code 0")
      expect(alive?(pid)).to be(true)
      master.write("1g")
      read_until(master, output, "PAUSED")
      slave.winsize = [8, 38]
      Process.kill(:WINCH, pid)
      master.write("f?")
      read_until(master, output, "close help")
      master.write("?q")
    end
    expect(status).to be_success
  end

  it "shows the selected Procfile from a custom working directory in the title" do
    write_file("app/config/Procfile.dev", "web: #{fixture('partial')}\n")
    status = with_terminal(*command("-d", "app", "-f", "app/config/Procfile.dev")) do |master, _slave, _pid, output|
      read_until(master, output, "config/Procfile.dev")
      expect(output).to include("/ app")
      master.write("q")
    end
    expect(status).to be_success
  end

  it "closes the TUI after an automatic policy shutdown and restores the terminal" do
    write_file("Procfile", "job: #{fixture('partial')}\n")
    status = with_terminal(*command("--exit-on", "any", "-t", "0.1")) do |master, _slave, _pid, output|
      read_until(master, output, "partial")
    end
    expect(status).to be_success
  end

  it "runs one-off commands with the original terminal and delivers signals directly" do
    pidfile = File.join(@directory, "run.pids")
    master, slave = PTY.open
    script = 'File.write(ARGV[0], Process.pid); puts "tty=" + STDIN.tty?.to_s; STDOUT.flush; sleep 30'
    pid = Process.spawn(*command("run", RbConfig.ruby, "-e", script, pidfile),
                        in: slave, out: slave, err: slave, pgroup: true, chdir: @directory)
    output = +""
    read_until(master, output, "tty=true")
    expect(File.read(pidfile).to_i).to eq(pid)
    Process.kill(:TERM, pid)
    eventually { !alive?(pid) }
    _pid, status = Process.waitpid2(pid)
    expect(status.termsig).to eq(Signal.list.fetch("TERM"))
    expect(output).not_to include(Foruiman::TUI::Terminal::ENTER)
  ensure
    if pid
      Process.kill(:KILL, -pid) if alive?(pid)
      begin
        Process.waitpid(pid)
      rescue Errno::ECHILD
        nil
      end
    end
    master&.close
    slave&.close
  end

  it "keeps watcher stdin open and forwards interactive debugger input" do
    write_file("Procfile", "watch: #{fixture('watch')}\nweb: #{fixture('input')}\n")
    status = with_terminal(*command) do |master, _slave, _pid, output|
      read_until(master, output, "watching")
      expect(output).not_to include("stdin closed")
      master.write("2i")
      read_until(master, output, "Input to web")
      master.write("continux")
      read_until(master, output, "continux")
      master.write("\x7fe\n")
      read_until(master, output, 'received "continue"')
      master.write("\x18")
      read_until(master, output, "Returned from web")
      master.write("q")
    end
    expect(status).to be_success
  end

  it "stops and starts a process with the same TUI key" do
    pidfile = File.join(@directory, "toggle.pids")
    write_file("Procfile", "web: #{fixture('ticker', pidfile)}\n")
    status = with_terminal(*command) do |master, _slave, _pid, output|
      read_until(master, output, "ready")
      first_pid = File.read(pidfile).to_i
      master.write("1s")
      read_until(master, output, "stopped")
      eventually { !alive?(first_pid) }
      master.write("s")
      read_until(master, output, "Starting web")
      eventually { File.read(pidfile).to_i != first_pid && alive?(File.read(pidfile).to_i) }
      master.write("q")
    end
    expect(status).to be_success
  end

  { "r on all" => "r", "R on all" => "R", "R on a process tab" => "1R" }.each do |label, keys|
    it "restarts every process with #{label} and cleans both generations" do
      pidfiles = %w[web worker].map { |name| File.join(@directory, "#{name}.pids") }
      write_file("Procfile", pidfiles.map do |file|
        "#{File.basename(file, '.pids')}: exec #{fixture('ticker', file)}\n"
      end.join)
      status = with_terminal(*command) do |master, _slave, _pid, output|
        read_until(master, output, "ready")
        eventually { pidfiles.all? { |file| File.exist?(file) && File.read(file).to_i.positive? } }
        old_pids = pidfiles.map { |file| File.read(file).to_i }
        write_file("history.pids", old_pids.join("\n"))
        master.write(keys)
        read_until(master, output, "Restarting all processes")
        eventually do
          bytes = master.read_nonblock(65_536, exception: false)
          output << bytes if bytes.is_a?(String)
          pidfiles.all? do |file|
            current = File.read(file).to_i
            current.positive? && !old_pids.include?(current) && alive?(current)
          end
        end
        expect(old_pids.select { |pid| alive?(pid) }).to be_empty
        master.write("q")
      end
      expect(status).to be_success
    end
  end

  { "s on all" => "s", "S on all" => "S", "S on a process tab" => "1S" }.each do |label, keys|
    it "stops every process with #{label} and keeps the interface open" do
      pidfiles = %w[web worker].map { |name| File.join(@directory, "#{name}.pids") }
      write_file("Procfile", pidfiles.map do |file|
        "#{File.basename(file, '.pids')}: exec #{fixture('ticker', file)}\n"
      end.join)
      status = with_terminal(*command) do |master, _slave, pid, output|
        read_until(master, output, "ready")
        eventually { pidfiles.all? { |file| File.exist?(file) && File.read(file).to_i.positive? } }
        members = pidfiles.map { |file| File.read(file).to_i }
        master.write(keys)
        read_until(master, output, "Stopping all processes")
        eventually { members.none? { |member| alive?(member) } }
        expect(alive?(pid)).to be(true)
        master.write("q")
      end
      expect(status).to be_success
    end
  end

  %w[INT TERM].each do |signal|
    it "cleans process groups and grandchildren after SIG#{signal}" do
      pidfile = File.join(@directory, "tree.pids")
      write_file("Procfile", "web: exec #{fixture('tree', pidfile)}\n")
      members = []
      status = with_terminal(*command) do |master, _slave, pid, output|
        read_until(master, output, "tree ready")
        members = File.read(pidfile).split.map(&:to_i)
        Process.kill(signal, pid)
        read_until(master, output, "Stopping process groups")
      end
      expect(status).to be_success
      expect(members.select { |member| alive?(member) }).to be_empty
    end
  end

  it "cleans grandchildren on normal quit during a pending restart" do
    pidfile = File.join(@directory, "restart.pids")
    write_file("Procfile", "web: exec #{fixture('tree', pidfile)}\n")
    members = []
    status = with_terminal(*command) do |master, _slave, _pid, output|
      read_until(master, output, "tree ready")
      members = File.read(pidfile).split.map(&:to_i)
      master.write("1r")
      read_until(master, output, "Restarting web")
      master.write("q")
    end
    expect(status).to be_success
    expect(members.select { |member| alive?(member) }).to be_empty
  end

  it "restores raw input and alternate screen after a renderer exception with grandchildren" do
    pidfile = File.join(@directory, "exception.pids")
    members = []
    status = with_terminal(RbConfig.ruby, "-I", File.expand_path("../../lib", __dir__),
                           File.expand_path("../fixtures/child.rb", __dir__),
                           "crash_tui", "exec #{fixture('tree', pidfile)}", pidfile) do |master, _slave, _pid, output|
      read_until(master, output, Foruiman::TUI::Terminal::ENTER)
      eventually { File.exist?(pidfile) }
      members = File.read(pidfile).split.map(&:to_i)
    end
    expect(status.exitstatus).to eq(17)
    expect(members.select { |member| alive?(member) }).to be_empty
  end

  it "restores the exact input mode after an exception" do
    master, slave = PTY.open
    terminal = Foruiman::TUI::Terminal.new(input: slave, output: slave)
    before = IO.popen(["stty", "-g"], in: slave, &:read)
    expect { terminal.session { raise "boom" } }.to raise_error("boom")
    after = IO.popen(["stty", "-g"], in: slave, &:read)
    expect(after).to eq(before)
  ensure
    master&.close
    slave&.close
  end

  it "uses plain output when only stdout is a TTY" do
    write_file("Procfile", "web: #{fixture('streams')}\n")
    master, slave = PTY.open
    pid = Process.spawn(*command, in: File::NULL, out: slave, err: slave, chdir: @directory)
    Process.waitpid(pid)
    output = master.read_nonblock(65_536)
    expect(output).to include("stdout message")
    expect(output).not_to include("\e[")
  ensure
    master&.close
    slave&.close
  end
  it "uses plain output when only stdin is a TTY" do
    write_file("Procfile", "web: #{fixture('streams')}\n")
    master, slave = PTY.open
    reader, writer = IO.pipe
    pid = Process.spawn(*command, in: slave, out: writer, err: writer, chdir: @directory)
    writer.close
    output = reader.read
    _pid, status = Process.waitpid2(pid)
    expect(status).to be_success
    expect(output).to include("stdout message")
    expect(output).not_to include("\e[")
  ensure
    [master, slave, reader, writer].compact.each { |io| io.close unless io.closed? }
  end
end
