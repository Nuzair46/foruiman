# frozen_string_literal: true

RSpec.describe "Plain mode" do
  it "waits for newline or EOF to print partial output" do
    write_file("Procfile", "web: #{fixture('partial')}\n")
    output, error, status = cli("start", "--no-tui")
    expect(status).to be_success
    expect(error).to be_empty
    messages = output.lines.select { |line| line.include?("[stdout]") }
    expect(messages.size).to eq(2)
    expect(messages.first).to end_with("partial line\n")
    expect(messages.last).to end_with("last\n")
  end

  it "drains a complete burst while keeping retained records bounded" do
    engine = build_engine({ "web" => fixture("burst", "25000") }, log_lines: 5)
    completed = 0
    engine.on_event { |event| completed += 1 if event.record&.complete && event.record.stream == :stdout }
    expect(engine.run).to eq(0)
    expect(completed).to eq(25_000)
    expect(engine.logs.all.size).to eq(5)
    expect(engine.logs["web"].size).to eq(5)
  end

  it "shuts down on SIGTERM with status 0 and no surviving child group" do
    pidfile = File.join(@directory, "child.pid")
    write_file("Procfile", "web: exec #{fixture('ticker', pidfile)}\n")
    input, output, errors, waiter = Open3.popen3(RbConfig.ruby, "-I", File.expand_path("../../lib", __dir__),
                                                 File.expand_path("../../bin/foruiman", __dir__),
                                                 chdir: @directory)
    input.close
    eventually { File.exist?(pidfile) }
    child = File.read(pidfile).to_i
    Process.kill(:TERM, waiter.pid)
    eventually { !waiter.alive? }
    expect(waiter.value).to be_success
    expect(alive?(child)).to be(false)
    expect(output.read).not_to include("\e[")
    expect(errors.read).to be_empty
  ensure
    if waiter&.alive?
      Process.kill(:KILL, waiter.pid)
      waiter.join
    end
    Process.kill(:KILL, -child) if child && alive?(child)
    [input, output, errors].compact.each { |io| io.close unless io.closed? }
  end
end
