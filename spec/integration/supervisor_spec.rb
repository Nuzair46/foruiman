# frozen_string_literal: true

RSpec.describe Foruiman::Engine do
  it "keeps peers alive when one process fails and returns failure after all finish" do
    engine = build_engine({ "bad" => fixture("exit", "7"), "peer" => fixture("ticker") })
    engine.start_all
    peer = engine.state("peer").pid
    eventually(engine) { engine.state("bad").pgid.nil? }
    expect(engine.state("bad").exit_status.exitstatus).to eq(7)
    expect(alive?(peer)).to be(true)
    expect(engine.finished?).to be(false)
    expect(engine.exit_code).to eq(1)
    engine.shutdown
    eventually(engine) { engine.finished? }
    expect(engine.exit_code).to eq(0)
    expect(alive?(peer)).to be(false)
  end

  it "returns 0 for success and 1 for failure, including shell command-not-found" do
    [0, 9].each do |code|
      engine = build_engine({ "web" => fixture("exit", code.to_s) })
      expect(engine.run).to eq(code.zero? ? 0 : 1)
    end
    expect(build_engine({ "missing" => "foruiman-command-that-does-not-exist" }).run).to eq(1)
  end

  it "restarts asynchronously, drains old output, and preserves logs and peer PID" do
    engine = build_engine({ "web" => fixture("ignore_term"), "peer" => fixture("ticker") })
    events = []
    engine.on_event { |event| events << event }
    engine.start_all
    eventually(engine) { engine.logs["web"].any? { |record| record.text.start_with?("ready") } }
    old_pid = engine.state("web").pid
    peer = engine.state("peer").pid
    old_records = engine.logs["web"].map(&:sequence)
    engine.restart("web")
    expect(engine.state("web").status).to eq(:restarting)
    engine.restart("web")
    eventually(engine) { engine.state("web").generation == 2 }
    expect(engine.state("web").pid).not_to eq(old_pid)
    expect(alive?(old_pid)).to be(false)
    expect(engine.state("peer").pid).to eq(peer)
    expect(alive?(peer)).to be(true)
    expect(engine.logs["web"].map(&:sequence)).to include(*old_records)
    expect(events.count { |event| event.type == :restarting }).to eq(1)
    expect(events.any? { |event| event.type == :killed }).to be(true)
    started = events.index { |event| event.type == :started && event.name == "web" && event.pid != old_pid }
    expect(events[(started + 1)..].none? { |event| event.record&.pid == old_pid }).to be(true)
  end

  it "restarts an exited process and supports stopping independently" do
    engine = build_engine({ "web" => fixture("exit", "0"), "peer" => fixture("ticker") })
    engine.start_all
    eventually(engine) { engine.state("web").pgid.nil? }
    engine.restart("web")
    expect(engine.state("web").generation).to eq(2)
    engine.stop("peer")
    eventually(engine) { engine.state("peer").pgid.nil? }
    expect(engine.state("peer").status).to eq(:stopped)
  end

  it "keeps managed stdin open for watchers and forwards debugger input through a TTY" do
    engine = build_engine({ "watch" => fixture("watch"), "web" => fixture("input") })
    engine.manage_input!
    engine.start_all
    eventually(engine) do
      engine.logs["watch"].any? { |record| record.text == "watching" } &&
        engine.logs["web"].any? { |record| record.text.include?("debug>") }
    end
    expect(engine.logs["watch"].map(&:text)).to include("stdin tty=true")
    expect(alive?(engine.state("watch").pid)).to be(true)
    expect(engine.write_input("web", "continue\n")).to be(true)
    eventually(engine) { engine.logs["web"].any? { |record| record.text.include?('received "continue"') } }
    expect(engine.logs["web"].map(&:text)).to include("stdin tty=true")
  end

  it "stops and starts one process without interrupting peers" do
    engine = build_engine({ "web" => fixture("ticker"), "peer" => fixture("ticker") })
    engine.start_all
    web = engine.state("web")
    peer_pid = engine.state("peer").pid
    first_pid = web.pid
    engine.stop("web")
    eventually(engine) { web.status == :stopped }
    expect(alive?(first_pid)).to be(false)
    expect(alive?(peer_pid)).to be(true)
    engine.start("web")
    eventually(engine) { web.status == :running && web.generation == 2 }
    expect(web.pid).not_to eq(first_pid)
    expect(engine.state("peer").pid).to eq(peer_pid)
  end

  %w[tree orphan].each do |mode|
    it "cleans up #{mode} descendants even after the leader exits" do
      pidfile = File.join(@directory, "pids")
      engine = build_engine({ "web" => "exec #{fixture(mode, pidfile)}" })
      engine.start_all
      eventually(engine) { File.exist?(pidfile) }
      pids = File.read(pidfile).split.map(&:to_i)
      expect(pids.size).to eq(3)
      engine.shutdown if mode == "tree"
      eventually(engine) { engine.finished? }
      expect(pids.select { |pid| alive?(pid) }).to be_empty
    end
  end

  it "cancels pending restarts during shutdown and kills grandchildren" do
    pidfile = File.join(@directory, "pids")
    engine = build_engine({ "web" => "exec #{fixture('tree', pidfile)}" })
    engine.start_all
    eventually(engine) { File.exist?(pidfile) }
    pids = File.read(pidfile).split.map(&:to_i)
    engine.restart("web")
    engine.shutdown
    eventually(engine) { engine.finished? }
    expect(engine.state("web").generation).to eq(1)
    expect(pids.select { |pid| alive?(pid) }).to be_empty
  end

  it "does not reap unrelated children" do
    unrelated = Process.spawn(RbConfig.ruby, "-e", "exit 23")
    engine = build_engine({ "web" => fixture("exit", "0") })
    engine.run
    _pid, status = Process.waitpid2(unrelated)
    expect(status.exitstatus).to eq(23)
  ensure
    begin
      Process.waitpid(unrelated) if unrelated
    rescue Errno::ECHILD
      nil
    end
  end

  it "restores pre-existing signal handlers even when an event consumer raises" do
    previous = Signal.trap(:TERM, "IGNORE")
    engine = build_engine({ "web" => fixture("ticker") })
    engine.on_event { raise "observer failed" }
    expect { engine.run }.to raise_error("observer failed")
    expect(alive?(engine.state("web").pid)).to be(false)
    expect(Signal.trap(:TERM, "DEFAULT")).to eq("IGNORE")
  ensure
    Signal.trap(:TERM, previous) if previous
  end

  it "retains bounded logs during bursts and continues to accept shutdown" do
    engine = build_engine({ "burst" => fixture("burst", "50000"), "long" => fixture("long") }, log_lines: 8)
    engine.start_all
    longest = 0
    10.times do
      before = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      engine.tick(timeout: 0.01)
      longest = [longest, Process.clock_gettime(Process::CLOCK_MONOTONIC) - before].max
    end
    engine.shutdown
    eventually(engine) { engine.finished? }
    expect(longest).to be < 0.5
    expect(engine.logs.all.size).to be <= 8
    expect(engine.logs["burst"].size).to be <= 8
    expect(engine.logs["long"].size).to be <= 8
  end
end
