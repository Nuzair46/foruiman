# frozen_string_literal: true

require "foruiman/tui/input_line"

RSpec.describe Foruiman::TUI::InputLine do
  subject(:editor) { described_class.new }

  it "edits before submitting, including backspace, delete and cursor movement" do
    expect(editor.feed("Settx\x7fings\e[D\e[D\e[3~g")).to eq([])
    expect(editor.feed("\r\n")).to eq([[:submit, "Settings"]])
    expect(editor.text).to eq("")
    expect(editor.feed("next\n")).to eq([[:submit, "next"]])
  end

  it "edits fragmented Unicode by grapheme and handles fragmented arrows" do
    "界é😀".bytes.each { |byte| editor.feed(byte.chr) }
    editor.feed("\e[")
    editor.feed("D\x7f")
    expect(editor.text).to eq("界😀")
    expect(editor.cursor).to eq(1)
  end

  it "recalls commands and restores the draft" do
    editor.feed("first\nsecond\nwork")
    editor.feed("\e[A")
    expect(editor.text).to eq("second")
    editor.feed("\e[A")
    expect(editor.text).to eq("first")
    editor.feed("\e[B\e[B")
    expect(editor.text).to eq("work")
  end

  it "returns explicit interrupt, EOF and detach events without leaking editing keys" do
    expect(editor.feed("abc\x01\x05\x15\x03\x04\x18q\n")).to eq(%i[interrupt eof detach])
    expect(editor.text).to eq("")
  end

  it "bounds pasted lines and incomplete escapes" do
    editor.feed("x" * 10_000)
    expect(editor.text.bytesize).to eq(described_class::MAX_BYTES)
    editor.feed("\x15\e[#{'9' * 1000}")
    expect(editor.feed("ok\n")).to eq([[:submit, "ok"]])
  end

  it "can always detach after an incomplete escape or UTF-8 sequence" do
    editor.feed("\e[")
    expect(editor.feed("\x18")).to eq([:detach])
    editor.feed("\xe3".b)
    expect(editor.feed("\x18q")).to eq([:detach])
  end
end
