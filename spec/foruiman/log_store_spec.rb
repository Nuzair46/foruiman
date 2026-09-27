# frozen_string_literal: true

RSpec.describe Foruiman::LogStore do
  def write(logs, name = "web", text = "line", **options)
    logs.write(name: name, text: text, stream: :stdout, pid: 1, complete: true, **options)
  end

  it "bounds both rings independently and shares frozen records" do
    logs = described_class.new(%w[web worker], capacity: 3)
    first = write(logs)
    expect(logs["web"][0]).to equal(logs.all[0])
    expect(first).to be_frozen
    expect(first.text).to be_frozen
    9.times { write(logs, "worker") }
    expect(logs["web"].size).to eq(1)
    expect(logs["worker"].size).to eq(3)
    expect(logs.all.map(&:sequence)).to eq([8, 9, 10])
    expect(logs.all.index_of(1)).to be_nil
    expect(logs.all.index_of(9)).to eq(1)
  end

  it "updates partial identity in O(1) without resurrecting an aggregate eviction" do
    logs = described_class.new(%w[web worker], capacity: 2)
    partial = logs.write(name: "web", stream: :stdout, pid: 1, text: "par", complete: false)
    3.times { write(logs, "worker") }
    complete = write(logs, "web", "partial", previous: partial)
    expect(complete.sequence).to eq(partial.sequence)
    expect(logs["web"][0]).to equal(complete)
    expect(logs.all.map(&:sequence)).to eq([3, 4])
    expect(partial.text).to eq("par")
  end

  it "keeps a process named all separate from the aggregate log" do
    logs = described_class.new(%w[all worker], capacity: 3)
    own = write(logs, "all", "own output")
    peer = write(logs, "worker", "peer output")
    expect(logs["all"].to_a).to eq([own])
    expect(logs[:all]).to equal(logs.all)
    expect(logs.all.to_a).to eq([own, peer])
  end

  [0, -1, 1.5, "10"].each do |capacity|
    it "rejects capacity #{capacity.inspect}" do
      expect { described_class.new(["web"], capacity: capacity) }.to raise_error(Foruiman::Error)
    end
  end
end
