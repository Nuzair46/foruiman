# frozen_string_literal: true

# Adapted execution/environment cases from Foreman's process_spec.rb.
RSpec.describe Foruiman::Process do
  def capture(command, env: ENV.to_h, custom_env: {})
    process = described_class.new(command, env: env, cwd: @directory)
    reader, writer = IO.pipe
    error_reader, error_writer = IO.pipe
    pid = process.run(output: writer, error: error_writer, env: custom_env)
    writer.close
    error_writer.close
    result = [reader.read, error_reader.read]
    Process.waitpid(pid)
    result
  ensure
    [reader, writer, error_reader, error_writer].compact.each { |io| io.close unless io.closed? }
    begin
      Process.kill(:KILL, -pid) if pid
      Process.waitpid(pid) if pid
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end
  end

  it "runs processes with distinct streams and UTF-8 output" do
    stdout, stderr = capture(fixture("streams"))
    expect(stdout).to eq("stdout message\n")
    expect(stderr).to eq("stderr message\n")
    expect(capture("printf '日本語\\n'").first).to eq("日本語\n")
  end

  it "lets the shell expand variable names, braces, quoting and pipelines" do
    command = %q(printf '%s\n' "$FOO" "${FOOBAR}" '$FOO' | /bin/cat)
    stdout, = capture(command, env: ENV.to_h.merge("FOO" => "first", "FOOBAR" => "second"),
                               custom_env: { "FOO" => "per run" })
    expect(stdout).to eq("per run\nsecond\n$FOO\n")
  end

  it "does not mutate the parent environment or working directory" do
    before = ENV.to_h
    cwd = Dir.pwd
    stdout, = capture(fixture("env", "FOO"), custom_env: { "FOO" => "bar" })
    expect(stdout).to include('"FOO":"bar"', '"stdin_eof":true', @directory)
    expect(ENV.to_h).to eq(before)
    expect(Dir.pwd).to eq(cwd)
  end
end
