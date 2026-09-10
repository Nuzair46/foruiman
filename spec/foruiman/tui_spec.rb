# frozen_string_literal: true

require "foruiman/tui/application"
require "foruiman/diagnostics"
require "stringio"

RSpec.describe Foruiman::TUI::Viewport do
  let(:logs) { Foruiman::LogStore.new(["web"], capacity: 5) }
  let(:buffer) { logs["web"] }
  subject(:viewport) { described_class.new }

  def append(text)
    logs.write(name: "web", stream: :stdout, pid: 1, text: text, complete: true)
  end

  before { 5.times { |index| append(index.to_s) } }

  it "follows new output until scrolled and anchors to identity across eviction" do
    expect(viewport.rows(buffer, 2).map(&:text)).to eq(%w[3 4])
    viewport.scroll(-1, buffer, 2)
    anchor = viewport.anchor
    append("5")
    expect(viewport.following).to be(false)
    expect(viewport.anchor).to eq(anchor)
    expect(viewport.rows(buffer, 2).map(&:text)).to eq(%w[2 3])
    3.times { |index| append((index + 6).to_s) }
    expect(viewport.rows(buffer, 2).map(&:text)).to eq(%w[4 5])
  end

  it "clamps on resize and resumes following with End" do
    viewport.scroll(0, buffer, 2)
    expect(viewport.rows(buffer, 4).map(&:text)).to eq(%w[1 2 3 4])
    viewport.home(buffer)
    expect(viewport.rows(buffer, 2).map(&:text)).to eq(%w[0 1])
    viewport.follow
    expect(viewport.rows(buffer, 2).map(&:text)).to eq(%w[3 4])
  end
end

RSpec.describe Foruiman::TUI::State do
  it "preserves ordered tabs and independent follow/scroll state" do
    state = described_class.new(%w[web worker])
    expect(state.tabs).to eq(%w[web worker all])
    expect(state.name).to eq("all")
    state.select(0)
    state.viewport.home(Foruiman::Ring.new(3))
    state.move(1)
    expect(state.viewport.following).to be(true)
    state.move(-1)
    expect(state.viewport.following).to be(false)
    state.move(-1)
    expect(state.name).to eq("all")
  end
end

RSpec.describe Foruiman::TUI::Keyboard do
  it "decodes fragmented sequences, numbers and shortcuts" do
    keyboard = described_class.new
    expect(keyboard.feed("\e[", now: 0)).to eq([])
    expect(keyboard.feed("A\t1rRi0q", now: 0.01)).to eq(
      [:up, :next, 1, :restart, :restart_all, :input, 0, :quit]
    )
    expect(keyboard.feed("\e[5~\e[6~\e[Z\x03")).to eq(%i[page_up page_down previous quit])
  end

  it "expires standalone Escape and ignores unknown escapes atomically" do
    keyboard = described_class.new
    expect(keyboard.feed("\e", now: 1)).to eq([])
    expect(keyboard.feed("", now: 1.2)).to eq([:escape])
    expect(keyboard.feed("\e[99Rq")).to eq([:quit])
    expect(keyboard.feed("\e[99", now: 2)).to eq([])
    expect(keyboard.feed("Rq", now: 2.01)).to eq([:quit])
  end
end

RSpec.describe Foruiman::TUI::Renderer do
  it "measures Unicode graphemes, wide characters, combining marks, and styles" do
    expect(described_class.width("\e[31m界é👩‍💻\e[0m")).to eq(5)
    text = described_class.truncate("\e[31m界é👩‍💻 tail", 3)
    expect(text).to eq("\e[31m界é\e[0m")
    expect(described_class.truncate("界", 1)).to eq("\e[0m")
  end

  it "keeps selected tabs visible and renders statuses, PID, help and tiny terminals" do
    names = Array.new(20) { |index| "process_#{index}" }
    engine = build_engine(names.to_h { |name| [name, fixture("exit", "0")] })
    engine.select("process_19")
    engine.start_all
    state = Foruiman::TUI::State.new(names)
    state.select(19)
    renderer = described_class.new
    frame = renderer.render(state, engine, rows: 10, columns: 45)
    expect(frame).to include("process_19", "PID #{engine.state('process_19').pid}")
    expect(frame.split("\r\n").size).to eq(10)
    state.help = true
    expect(renderer.render(state, engine, rows: 15, columns: 100)).to include("Restart selected")
    expect(renderer.render(state, engine, rows: 1, columns: 1)).to include("\e[H")
    engine.shutdown
    expect(renderer.render(state, engine, rows: 10, columns: 80)).to include("Stopping process groups")
  end

  it "resets styles on every row and truncates without wrapping" do
    engine = build_engine({ "web" => fixture("exit", "0") })
    engine.start_all
    engine.logs.write(name: "web", stream: :stdout, pid: 1, text: "\e[31m#{'界' * 100}", complete: false)
    state = Foruiman::TUI::State.new(["web"])
    frame = described_class.new.render(state, engine, rows: 8, columns: 40)
    frame.delete_prefix("\e[H").split("\r\n").each do |line|
      expect(line).to end_with("\e[0m")
      expect(described_class.width(line.delete_prefix("\e[2K"))).to be <= 39
    end
  end
end

RSpec.describe Foruiman::TUI::Application do
  it "restarts running and exited entries on all without losing retained logs" do
    engine = build_engine({ "web" => fixture("ticker"), "job" => fixture("exit", "0") })
    engine.start_all
    eventually(engine) { engine.state("job").status == :exited && engine.logs["web"].any? }
    retained = engine.logs.all.map(&:sequence)
    application = described_class.new(engine)
    application.handle(:restart, 10)
    eventually(engine) { engine.processes.all? { |entry| entry.generation == 2 } }
    expect(application.state.feedback).to eq("Restarting all processes")
    expect(engine.logs.all.map(&:sequence)).to include(*retained)
  end

  it "enters child input mode and toggles the selected process between running and stopped" do
    engine = build_engine({ "web" => fixture("ticker") })
    engine.start_all
    application = described_class.new(engine)
    application.state.select(0)
    application.handle(:input, 10)
    expect(application.state.input_target).to eq("web")
    application.handle(:stop, 10)
    eventually(engine) { engine.state("web").status == :stopped }
    expect(application.state.feedback).to eq("Stopping web")
    application.handle(:stop, 10)
    expect(engine.state("web").status).to eq(:running)
    expect(application.state.feedback).to eq("Starting web")
  end

  it "stays open after children exit and processes restart, tab and quit input" do
    engine = build_engine({ "web" => fixture("exit", "0") })
    terminal = double("terminal", size: [12, 80], draw: nil)
    allow(terminal).to receive(:session).and_yield
    phase = 0
    allow(terminal).to receive(:read) do
      if phase.zero? && engine.finished?
        phase = 1
        "1r"
      elsif phase == 1 && engine.state("web").generation == 2 && engine.finished?
        phase = 2
        "q"
      else
        :wait_readable
      end
    end
    expect(Timeout.timeout(5) { described_class.new(engine, terminal: terminal).run }).to eq(0)
    expect(phase).to eq(2)
    expect(engine.state("web").generation).to eq(2)
  end

  it "restores terminal and cleans up when drawing raises" do
    engine = build_engine({ "web" => fixture("ticker") })
    terminal = double("terminal", size: [12, 80], read: :wait_readable)
    restored = false
    allow(terminal).to receive(:session) do |&block|
      block.call
    ensure
      restored = true
    end
    allow(terminal).to receive(:draw).and_raise("drawing failed")
    expect { described_class.new(engine, terminal: terminal).run }.to raise_error("drawing failed")
    expect(restored).to be(true)
    expect(alive?(engine.state("web").pid)).to be(false)
  end
end

RSpec.describe Foruiman::Diagnostics do
  it "writes interactive errors to a private persistent temporary file" do
    stderr = StringIO.new
    diagnostics = described_class.new(interactive: true, stderr: stderr)
    diagnostics.error(RuntimeError.new("debug detail"))
    diagnostics.close
    expect(stderr.string).to be_empty
    expect(File.stat(diagnostics.path).mode & 0o777).to eq(0o600)
    expect(File.read(diagnostics.path)).to include("debug detail")
  ensure
    File.unlink(diagnostics.path) if diagnostics&.path && File.exist?(diagnostics.path)
  end

  it "writes plain-mode errors to stderr" do
    stderr = StringIO.new
    described_class.new(interactive: false, stderr: stderr).error(RuntimeError.new("plain detail"))
    expect(stderr.string).to include("plain detail")
  end
end

RSpec.describe "Terminal theme and layout" do
  def preview(names = %w[web worker assets jobs])
    states = names.each_with_index.map do |name, index|
      Foruiman::Engine::State.new(name: name, pid: 42_000 + index, port: 5000 + (index * 100),
                                  status: index == 3 ? :failed : :running, generation: 1)
    end
    logs = Foruiman::LogStore.new(names, capacity: 100)
    50.times do |index|
      logs.write(name: names[index % names.size], stream: :stdout, pid: 1,
                 text: "line #{index} with \e[31mcolored output\e[0m and wide text 界", complete: true)
    end
    engine = double("engine", root: @directory, procfile_path: File.join(@directory, "Procfile"),
                              processes: states, process_names: names,
                              logs: logs, shutting_down?: false)
    allow(engine).to receive(:state) { |name| states.find { |entry| entry.name == name } }
    [Foruiman::TUI::State.new(names), engine]
  end

  def plain_rows(frame)
    frame.gsub(/\e\[[0-9;:]*[A-Za-z]/, "").split("\r\n", -1)
  end

  it "uses theme-controlled ANSI colors and default backgrounds regardless of truecolor support" do
    [{ "COLORTERM" => "truecolor" }, { "TERM" => "xterm-256color" }].each do |env|
      theme = Foruiman::TUI::Theme.new(env: env)
      expect(theme.paint("hello")).to include("\e[39m", "\e[49m", "hello")
      expect(theme.paint("failed", :red)).to include("\e[31m")
      expect(theme.paint("selected", selected: true)).to include("\e[39m\e[49m\e[7mselected")
      state, engine = preview
      frame = Foruiman::TUI::Renderer.new(theme: theme).render(state, engine, rows: 24, columns: 100)
      expect(frame).not_to match(/\e\[(?:38|48)[;:]/)
    end
  end

  it "keeps a visible selection without colors and strips child colors for NO_COLOR" do
    disabled = Foruiman::TUI::Theme.new(env: { "COLORTERM" => "truecolor", "NO_COLOR" => "1" })
    expect(disabled.paint("hello")).to eq("hello")
    expect(disabled.paint("selected", selected: true)).to eq("\e[7mselected\e[0m")
    expect(disabled.log("\e[31mred\e[0m plain")).to eq("red plain")
    expect(Foruiman::TUI::Theme.new(env: { "TERM" => "dumb" }).enabled).to be(false)
  end

  it "restores the theme after child resets while preserving explicit child backgrounds" do
    theme = Foruiman::TUI::Theme.new(env: { "COLORTERM" => "truecolor" })
    output = theme.log("\e[41mchild\e[0mnormal\e[38;2;10;20;30m custom")
    expect(output).to include("\e[41mchild", "\e[0m#{theme.base}normal", "\e[38;2;10;20;30m custom")
    expect(output).to end_with(theme.reset)
  end

  it "fits every row and retains a visible selected tab across narrow and wide layouts" do
    state, engine = preview(%w[web worker assets jobs scheduler mailer notifications])
    renderer = Foruiman::TUI::Renderer.new(theme: Foruiman::TUI::Theme.new(env: { "COLORTERM" => "truecolor" }))
    [[24, 10], [45, 12], [59, 13], [60, 14], [80, 24], [120, 30]].each do |columns, rows|
      state.tabs.each_index do |selection|
        state.select(selection)
        frame = renderer.render(state, engine, rows: rows, columns: columns)
        rendered = plain_rows(frame)
        expect(rendered.size).to eq(rows)
        expect(rendered.map { |row| Foruiman::TUI::Text.width(row) }.max).to be <= columns - 1
        tab_row = rendered[Foruiman::TUI::Renderer.expanded?(rows: rows, columns: columns) ? 2 : 1]
        expect(tab_row).to include(state.name[0, 3])
      end
    end
  end

  it "uses the same viewport height for rendering and keyboard paging, including after resize" do
    state, engine = preview
    renderer = Foruiman::TUI::Renderer.new
    [[120, 30], [45, 12], [80, 24]].each do |columns, rows|
      frame = renderer.render(state, engine, rows: rows, columns: columns)
      height = Foruiman::TUI::Renderer.log_height(rows: rows, columns: columns)
      expect(plain_rows(frame).count { |line| line.include?("out │") }).to eq(height)
      expect(state.viewport.rows(engine.logs.all, height).last.text).to include("line 49")
    end
  end

  it "shows failure details and highlights paused scroll position" do
    state, engine = preview
    status = instance_double(Process::Status, exitstatus: 7)
    engine.state("jobs").exit_status = status
    state.select(3)
    state.viewport.home(engine.logs["jobs"])
    renderer = Foruiman::TUI::Renderer.new
    rendered = plain_rows(renderer.render(state, engine, rows: 20, columns: 110)).join("\n")
    expect(rendered).to include("failed", "PID 42003", "exit 7", "PAUSED", "f resume")
  end

  it "treats terminal controls in project directory names as text, never screen commands" do
    state, engine = preview
    root = "/work/hello\e[2J\e]52;c;test\a"
    allow(engine).to receive(:root).and_return(root)
    allow(engine).to receive(:procfile_path).and_return(File.join(root, "Procfile"))
    frame = Foruiman::TUI::Renderer.new.render(state, engine, rows: 24, columns: 100)
    expect(frame).not_to include("\e[2J", "\e]52;")
    expect(frame).to include("hello")
  end

  it "prioritizes the active Procfile in the title across terminal sizes" do
    state, engine = preview
    allow(engine).to receive(:root).and_return("/work/atlas")
    allow(engine).to receive(:procfile_path).and_return("/work/atlas/config/Procfile.dev")
    renderer = Foruiman::TUI::Renderer.new
    [24, 45, 60, 80, 120].each do |columns|
      title = plain_rows(renderer.render(state, engine, rows: 24, columns: columns)).first
      expect(title).to include("Procfile.dev")
      expect(Foruiman::TUI::Text.width(title)).to be <= columns - 1
    end
    title = plain_rows(renderer.render(state, engine, rows: 24, columns: 120)).first
    expect(title).to include("/ atlas", "config/Procfile.dev")
    allow(engine).to receive(:procfile_path).and_return("/work/shared/Procfile.dev")
    title = plain_rows(renderer.render(state, engine, rows: 24, columns: 120)).first
    expect(title).to include("../shared/Procfile.dev")
  end

  it "sanitizes terminal controls in Procfile names and clips long Unicode paths" do
    state, engine = preview
    name = "#{'界' * 80}é\e[2J\e]52;c;test\a.dev"
    allow(engine).to receive(:procfile_path).and_return(File.join(@directory, name))
    frame = Foruiman::TUI::Renderer.new.render(state, engine, rows: 24, columns: 80)
    expect(frame).not_to include("\e[2J", "\e]52;")
    title = plain_rows(frame).first
    expect(title).to include("界", "…")
    expect(Foruiman::TUI::Text.width(title)).to be <= 79
  end

  it "labels the restart shortcut for the current tab" do
    state, engine = preview
    renderer = Foruiman::TUI::Renderer.new
    expect(plain_rows(renderer.render(state, engine, rows: 24, columns: 100)).last).to include("restart all")
    state.select(0)
    footer = plain_rows(renderer.render(state, engine, rows: 24, columns: 100)).last
    expect(footer).to include("restart")
    expect(footer).not_to include("restart all")
  end

  it "shows clear running and stopped glyphs with a state-aware start/stop action" do
    state, engine = preview
    state.select(0)
    renderer = Foruiman::TUI::Renderer.new
    running = plain_rows(renderer.render(state, engine, rows: 24, columns: 100)).join("\n")
    expect(running).to include("▶", "■ stop")
    engine.state("web").status = :stopped
    stopped = plain_rows(renderer.render(state, engine, rows: 24, columns: 100)).join("\n")
    expect(stopped).to include("■", "▶ start")
  end
end
