# frozen_string_literal: true

# Adapted from upstream spec/foreman/procfile_spec.rb; see docs/UPSTREAM.md.
RSpec.describe Foruiman::Procfile do
  subject(:procfile) { described_class.new }

  it "loads a passed-in file and preserves ordered names" do
    file = write_file("Procfile", "alpha: ./alpha\nbravo: ./bravo\nfoo-bar: ./foo-bar\nfoo_bar: ./foo_bar\n")
    loaded = described_class.new(file)
    expect(loaded.entries.map(&:first)).to eq(%w[alpha bravo foo-bar foo_bar])
    expect(loaded["alpha"]).to eq("./alpha")
    expect(loaded["unicorn"]).to be_nil
    procfile.load(file)
    expect(procfile["bravo"]).to eq("./bravo")
  end

  it "can append, replace, delete, and serialize entries" do
    procfile["foo"] = "./foo"
    procfile["bar"] = "./bar"
    expect(procfile.to_s).to eq("foo: ./foo\nbar: ./bar")
    procfile["foo"] = "./new"
    expect(procfile.entries.map(&:first)).to eq(%w[bar foo])
    filename = File.join(@directory, "Procfile")
    procfile.save(filename)
    expect(File.read(filename)).to eq("bar: ./bar\nfoo: ./new\n")
    procfile.delete("bar")
    expect(procfile["bar"]).to be_nil
  end

  it "ignores blank lines and comments and supports CRLF" do
    file = write_file("Procfile", "# comment\r\n  # comment\r\n\r\nweb: echo hi\r\n")
    expect(described_class.new(file)["web"]).to eq("echo hi")
  end

  it "preserves internal and trailing command whitespace" do
    file = write_file("Procfile", "web:\t  printf 'a  b'  && echo done  \n")
    expect(described_class.new(file)["web"]).to eq("printf 'a  b'  && echo done  ")
  end

  it "rejects empty files" do
    file = write_file("Procfile", "\n# only a comment\n")
    expect { described_class.new(file) }.to raise_error(described_class::EmptyFileError, /no processes/)
  end

  ["web echo hi", "bad.name: echo hi", "web:  ", "all: echo hi", "web: echo\0"].each do |line|
    it "rejects #{line.inspect} with a line number" do
      file = write_file("Procfile", "# line 1\n#{line}\n")
      expect { described_class.new(file) }.to raise_error(described_class::ParseError, /Procfile:2:/)
    end
  end

  it "rejects duplicates before replacing any previously loaded entries" do
    procfile["existing"] = "echo old"
    file = write_file("Procfile", "web: echo first\nweb: echo second\n")
    expect { procfile.load(file) }.to raise_error(described_class::ParseError, /:2: duplicate 'web'.*line 1/)
    expect(procfile["existing"]).to eq("echo old")
  end
end
