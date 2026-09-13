# frozen_string_literal: true

require "foruiman/configuration"
require "json"

RSpec.describe "Foreman compatibility" do
  def env_procfile(path = "Procfile")
    write_file(path, "web: #{fixture('env', 'A', 'B', 'PORT', 'PS')}\n")
  end

  it "takes the port from .env, inherited environment, then 5000 with -p taking precedence" do
    env_procfile
    output, _error, status = cli("start", env: { "PORT" => nil })
    expect(status).to be_success
    expect(output).to include('"PORT":"5000"')
    output, = cli("start", env: { "PORT" => "6100" })
    expect(output).to include('"PORT":"6100"')
    write_file(".env", "PORT=7200\n")
    output, = cli("start", env: { "PORT" => "6100" })
    expect(output).to include('"PORT":"7200"')
    output, = cli("start", "-p", "8300", env: { "PORT" => "6100" })
    expect(output).to include('"PORT":"8300"')
  end

  it "loads comma-separated files left to right, replacing default .env" do
    env_procfile
    write_file(".env", "A=default\nB=default\n")
    write_file("first.env", "A=first\nPORT=6000\n")
    write_file("last.env", "A=last\n")
    output, error, status = cli("start", "-e", "first.env,last.env", env: { "B" => "parent" })
    expect(status).to be_success
    expect(error).to be_empty
    expect(output).to include('"A":"last"', '"B":"parent"', '"PORT":"6000"')
  end

  it "uses .foreman defaults and lets CLI values, including false, override them" do
    env_procfile("app/Procfile.dev")
    write_file("app/.env", "A=default\nPORT=8000\n")
    write_file(".foreman",
               "root: app\nprocfile: app/Procfile.dev\nport: 7000\ndotenv: true\nexit-on: any\ntimeout: 0.1\n")
    output, error, status = cli("start", env: { "PORT" => "6000" })
    expect(status).to be_success
    expect(error).to be_empty
    expect(output).to include('"A":"default"', '"PORT":"7000"', %("cwd":"#{@directory}/app"))
    output, error, status = cli("start", "--no-dotenv", "-p", "9000", env: { "A" => "parent" })
    expect(status).to be_success
    expect(error).to be_empty
    expect(output).to include('"A":"parent"', '"PORT":"9000"')
  end

  it "resolves explicit Procfiles and environment files from invocation even with a different root" do
    env_procfile("config/Procfile")
    write_file("app/.env", "A=app\n")
    write_file(".env", "A=invocation\n")
    write_file("custom.env", "A=explicit\n")
    output, = cli("start", "-f", "config/Procfile")
    expect(output).to include('"A":"invocation"', %("cwd":"#{@directory}/config"))
    output, = cli("start", "-d", "app", "-f", "config/Procfile")
    expect(output).to include('"A":"app"', %("cwd":"#{@directory}/app"))
    output, = cli("start", "-d", "app", "-f", "config/Procfile", "-e", "custom.env")
    expect(output).to include('"A":"explicit"', %("cwd":"#{@directory}/app"))
  end

  ["[]", "port: [5000]", "tui: nope", "root: false", "formation: web=2", "!ruby/object:Object {}",
   "port: ["].each do |yaml|
    it "rejects invalid or unsupported .foreman content: #{yaml}" do
      env_procfile
      write_file(".foreman", yaml)
      output, error, status = cli("check")
      expect(status.exitstatus).to eq(1)
      expect(error).not_to be_empty
      expect(output).not_to include("valid Procfile")
    end
  end

  { "--timeout" => %w[-1 NaN Infinity nope], "--exit-on" => %w[unknown],
    "-e" => ["missing", "a,,b"] }.each do |option, values|
    values.each do |value|
      it "rejects #{option} #{value} before startup" do
        env_procfile
        _output, error, status = cli("start", option, value)
        expect(status.exitstatus).to eq(1)
        expect(error).not_to be_empty
      end
    end
  end

  it "checks allocations from environment-derived ports before spawning" do
    write_file("Procfile", "web: echo never\nworker: echo never\n")
    write_file(".env", "PORT=65500\n")
    output, error, status = cli("start")
    expect(status.exitstatus).to eq(1)
    expect(error).to include("65600")
    expect(output).to be_empty
  end

  it "runs an arbitrary command without a Procfile and preserves arguments, streams and exit code" do
    write_file(".env", "A=dotenv\nPORT=6123\n")
    script = 'require "json"; puts JSON.generate([ARGV, ENV["A"], ENV["PORT"], STDIN.read]); warn "separate"; exit 23'
    output, error, status = cli("run", RbConfig.ruby, "-e", script, "--", "a b", "$(touch unexpected)", "--port", "99")
    expect(status.exitstatus).to eq(23)
    expect(JSON.parse(output)).to eq([["a b", "$(touch unexpected)", "--port", "99"], "dotenv", "6123", ""])
    expect(error).to eq("separate\n")
    expect(File).not_to exist(File.join(@directory, "unexpected"))
  end

  it "runs a named Procfile command through the shell without generating PORT or PS" do
    write_file("Procfile", "web: #{fixture('env', 'A', 'PORT', 'PS')}\n")
    write_file("custom.env", "A=custom\nPORT=6123\n")
    output, error, status = cli("run", "-e", "custom.env", "web", env: { "PS" => nil })
    expect(status).to be_success
    expect(error).to be_empty
    expect(JSON.parse(output)).to include("A" => "custom", "PORT" => "6123")
    expect(JSON.parse(output)).not_to have_key("PS")
  end

  it "passes stdin directly to run commands" do
    output, error, status = Open3.capture3(RbConfig.ruby, "-I", File.expand_path("../../lib", __dir__),
                                           File.expand_path("../../bin/foruiman", __dir__), "run", RbConfig.ruby,
                                           "-e", "print STDIN.read", stdin_data: "hello\n", chdir: @directory)
    expect(status).to be_success
    expect(output).to eq("hello\n")
    expect(error).to be_empty
  end

  it "reports missing run commands clearly" do
    [[], ["foruiman-no-such-command"]].each do |args|
      _output, error, status = cli("run", *args)
      expect(status.exitstatus).to eq(1)
      expect(error).not_to be_empty
    end
  end

  it "wires shutdown policy and fractional timeout into the CLI" do
    write_file("Procfile", "job: #{fixture('exit', '7')}\n")
    _output, error, status = cli("start", "--exit-on", "any", "-t", "0.05")
    expect(error).to be_empty
    expect(status.exitstatus).to eq(7)
  end
end
