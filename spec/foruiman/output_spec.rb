# frozen_string_literal: true

RSpec.describe Foruiman::Output do
  let(:events) { [] }
  let(:logs) { Foruiman::LogStore.new(["web"], capacity: 10) { |record| events << record } }
  subject(:output) { described_class.new(logs, name: "web", stream: :stdout, pid: 123) }

  it "publishes partial lines live and completes the same record on newline and EOF" do
    output.feed("par")
    sequence = logs.all[0].sequence
    expect(logs.all[0].complete).to be(false)
    output.feed("tial\nlast")
    expect(logs.all[0].sequence).to eq(sequence)
    expect(logs.all[0].text).to eq("partial")
    expect(logs.all[0].complete).to be(true)
    output.feed("", eof: true)
    expect(logs.all.map(&:text)).to eq(%w[partial last])
    expect(events.select(&:complete).map(&:text)).to eq(%w[partial last])
  end

  it "handles fragmented UTF-8 and ANSI, preserving only styles" do
    bytes = "\e[31m赤😀\e[2J\e]52;c;clipboard\a\ePpayload\e\\\n"
    bytes.bytes.each { |byte| output.feed(byte.chr) }
    expect(logs.all.size).to eq(1)
    expect(logs.all[0].text).to eq("\e[31m赤😀")
    output.feed("next\n")
    expect(logs.all[1].text).to eq("\e[31mnext")
  end

  it "replaces invalid bytes and flushes an incomplete UTF-8 character on EOF" do
    output.feed("a\xffb\xe3".b)
    output.feed("", eof: true)
    expect(logs.all[0].text).to eq("a�b�")
  end

  it "bounds unterminated escape payloads and newline-free output" do
    output.feed("\e]52;c;#{'x' * 100_000}")
    output.feed("\a#{'界' * 30_000}")
    output.feed("", eof: true)
    expect(logs.all.size).to be <= 10
    expect(events.map { |record| record.text.bytesize }.max).to be <= described_class::MAX_BYTES
    expect(events.all? { |record| record.text.valid_encoding? }).to be(true)
    expect(events.select(&:complete).sum { |record| record.text.count("界") }).to eq(30_000)
  end

  it "keeps styles bounded over repeated changes and resets at a reset sequence" do
    output.feed("#{"\e[31m" * 1000}x\n\e[0mreset\nplain\n")
    expect(logs.all.to_a.last.text).to eq("plain")
    expect(logs.all.to_a[-2].text).to eq("\e[31m\e[0mreset")
  end
  it "does not invent a blank line when a newline follows the size boundary" do
    output.feed("x" * described_class::MAX_BYTES)
    output.feed("\n\nlast\n")
    expect(events.select(&:complete).map(&:text)).to eq(["x" * described_class::MAX_BYTES, "", "last"])
  end

  it "suppresses UTF-8 C1 controls, including CSI and OSC introducers" do
    output.feed("safe\u009b2J\u009d52;clipboard\n")
    expect(logs.all[0].text).not_to match(/[\u0080-\u009f\e]/)
  end

  it "produces the same complete text under different byte fragmentation" do
    source = "\e[38;2;10;20;30m界👩‍💻 combining é\n" * 15
    reference = []
    [1, 2, 3, 17, 1024].each do |chunk_size|
      records = []
      store = Foruiman::LogStore.new(["web"], capacity: 3) { |record| records << record.text if record.complete }
      stream = described_class.new(store, name: "web", stream: :stdout, pid: 1)
      source.b.bytes.each_slice(chunk_size) { |bytes| stream.feed(bytes.pack("C*")) }
      stream.feed("", eof: true)
      reference = records if reference.empty?
      expect(records).to eq(reference)
    end
  end
end
