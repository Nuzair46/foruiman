# frozen_string_literal: true

class Foruiman::Ring
  include Enumerable

  attr_reader :capacity, :size

  def initialize(capacity)
    raise Foruiman::Error, "log-lines must be a positive integer" unless capacity.is_a?(Integer) && capacity.positive?

    @capacity = capacity
    @slots = []
    @positions = {}
    @head = 0
    @size = 0
  end

  def append(record)
    index = (@head + @size) % capacity
    if size == capacity
      @positions.delete(@slots[index].sequence)
      @head = (@head + 1) % capacity
    else
      @size += 1
    end
    @slots[index] = record
    @positions[record.sequence] = index
    record
  end

  def replace(record)
    index = @positions[record.sequence]
    @slots[index] = record if index
    record
  end

  def [](index)
    return unless index >= 0 && index < size

    @slots[(@head + index) % capacity]
  end

  def index_of(sequence)
    position = @positions[sequence]
    (position - @head) % capacity if position
  end

  def each
    return enum_for(:each) unless block_given?

    size.times { |index| yield self[index] }
  end
end
