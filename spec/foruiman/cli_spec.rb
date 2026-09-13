# frozen_string_literal: true

RSpec.describe "CLI" do
  it "prints its version and excludes unsupported commands" do
    output, error, status = cli("--version")
    expect(output).to eq("#{Foruiman::VERSION}\n")
    expect(error).to be_empty
    expect(status).to be_success
    %w[export tree].each do |command|
      _output, _error, status = cli(command)
      expect(status).not_to be_success
    end
  end

  it "checks without spawning and rejects malformed entries atomically" do
    marker = File.join(@directory, "spawned")
    write_file("Procfile", "web: #{fixture('ticker', marker)}\nbroken\n")
    _output, error, status = cli("start", "--no-tui")
    expect(status.exitstatus).to eq(1)
    expect(error).to include("Procfile:2:")
    expect(File).not_to exist(marker)
    write_file("Procfile", "web: #{fixture('ticker', marker)}\n")
    output, _error, status = cli("check")
    expect(status).to be_success
    expect(output).to include("web")
    expect(File).not_to exist(marker)
  end

  ["0", "-1", "1.5", "nope"].each do |capacity|
    it "rejects log capacity #{capacity}" do
      write_file("Procfile", "web: #{fixture('streams')}\n")
      _output, error, status = cli("start", "--log-lines", capacity)
      expect(status.exitstatus).to eq(1)
      expect(error).to include("log-lines")
    end
  end

  %w[0 -1 65536 12.3 nope].each do |port|
    it "rejects port #{port}" do
      write_file("Procfile", "web: #{fixture('streams')}\n")
      _output, error, status = cli("check", "-p", port)
      expect(status.exitstatus).to eq(1)
      expect(error).to include("port")
    end
  end

  it "validates the last allocation and rejects unknown options" do
    write_file("Procfile", "web: echo web\nworker: echo worker\n")
    _output, error, status = cli("start", "-p", "65500")
    expect(status.exitstatus).to eq(1)
    expect(error).to include("65600")
    _output, error, status = cli("start", "--formation", "web=2")
    expect(status.exitstatus).to eq(1)
    expect(error).to include("Unknown switches")
  end

  it "replaces .env with explicit files and infers the root from the Procfile" do
    write_file("nested/Procfile", "web: #{fixture('env', 'FOO', 'BAR', 'PORT', 'PS')}\n")
    write_file(".env", "FOO=dotenv\nBAR=dotenv\nPORT=9000\nPS=wrong\n")
    write_file("custom.env", "FOO=explicit\n")
    output, error, status = cli("-f", "nested/Procfile", "-e", "custom.env",
                                env: { "FOO" => "inherited", "BAR" => "inherited", "PORT" => "7000" })
    expect(status).to be_success
    expect(error).to be_empty
    expect(output).to include('"FOO":"explicit"', '"BAR":"inherited"', '"PORT":"7000"', '"PS":"web.1"')
    expect(output).to include(%("cwd":"#{@directory}/nested"))
    expect(output).not_to include("\e[")
  end

  it "supports a custom root and a selected process with its original port" do
    write_file("app/Procfile", "web: #{fixture('streams')}\nworker: #{fixture('env', 'PORT')}\n")
    output, _error, status = cli("start", "worker", "-d", "app", "-p", "6000")
    expect(status).to be_success
    expect(output).to include('"PORT":"6100"', %("cwd":"#{@directory}/app"))
    expect(output).not_to include("stdout message")
    _output, error, status = cli("start", "unknown", "-d", "app")
    expect(status.exitstatus).to eq(1)
    expect(error).to include("unknown process")
  end

  it "does not load terminal libraries in plain mode" do
    command = [RbConfig.ruby, "-I", File.expand_path("../../lib", __dir__), "-rforuiman/cli", "-e",
               'puts $LOADED_FEATURES.grep(/io\/console|tui\/|unicode\/display_width/)']
    output, _error, status = Open3.capture3(*command)
    expect(status).to be_success
    expect(output).to be_empty
  end
end
