# frozen_string_literal: true

# Quoting cases retained from Foreman's engine_spec.rb environment examples.
RSpec.describe Foruiman::Env do
  it "reads unquoted, single-quoted, double-quoted and escaped values" do
    file = write_file("env", <<~'ENV')
      FOO=bar
      BAZ="qux"
      FRED='barney'
      OTHER="escaped\"quote"
      URL="http://example.com/api?foo=bar&baz=1"
      MULTI="bar\nbaz"
      LITERAL='bar\nbaz'
      EMPTY=
      # comment
      invalid assignment
    ENV
    expect(described_class.new(file).to_h).to eq(
      "FOO" => "bar", "BAZ" => "qux", "FRED" => "barney", "OTHER" => 'escaped"quote',
      "URL" => "http://example.com/api?foo=bar&baz=1", "MULTI" => "bar\nbaz", "LITERAL" => 'bar\nbaz', "EMPTY" => ""
    )
  end

  it "layers inherited, .env, and explicit values without mutating ENV or its input" do
    before = ENV.to_h
    inherited = { "A" => "inherited", "B" => "inherited", "C" => "inherited" }.freeze
    write_file(".env", "A=dotenv\nB=dotenv\n")
    explicit = write_file("custom.env", "A=explicit\n")
    result = described_class.load(root: @directory, file: explicit, inherited: inherited)
    expect(result).to eq("A" => "explicit", "B" => "dotenv", "C" => "inherited")
    expect(ENV.to_h).to eq(before)
    expect(inherited["A"]).to eq("inherited")
  end

  it "allows disabling .env while still loading the explicit file" do
    write_file(".env", "A=default\n")
    file = write_file("custom.env", "B=custom\n")
    expect(described_class.load(root: @directory, file: file, dotenv: false, inherited: {})).to eq("B" => "custom")
  end

  it "fails for a missing explicit file but allows absent .env" do
    expect(described_class.load(root: @directory, inherited: {})).to eq({})
    expect { described_class.load(root: @directory, file: "#{@directory}/missing") }.to raise_error(Errno::ENOENT)
  end
end
