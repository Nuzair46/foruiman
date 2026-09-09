# frozen_string_literal: true

require_relative "ring"

class Foruiman::LogStore
  Record = Data.define(:sequence, :name, :stream, :pid, :time, :text, :complete)
  attr_reader :all

  def initialize(names, capacity: 10_000, &listener)
    @all = Foruiman::Ring.new(capacity)
    @buffers = names.to_h { |name| [name, Foruiman::Ring.new(capacity)] }
    @sequence = 0
    @listener = listener
  end

  def [](name)
    name == "all" ? all : @buffers.fetch(name)
  end

  def write(name:, stream:, pid:, text:, complete:, previous: nil)
    @sequence += 1 unless previous
    record = Record.new(sequence: previous ? previous.sequence : @sequence, name: name,
                        stream: stream, pid: pid, time: previous ? previous.time : Time.now.freeze,
                        text: text.dup.freeze, complete: complete)
    method = previous ? :replace : :append
    @buffers.fetch(name).public_send(method, record)
    all.public_send(method, record)
    @listener&.call(record)
    record
  end
end
