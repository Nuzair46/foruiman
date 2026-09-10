# Architecture and embedding

`Procfile` retains Foreman's ordered parser/writer API with strict file validation.
`Env` retains its quoting rules and adds a non-mutating precedence merge. `Process`
wraps `/bin/sh -c` with a new process group, two output streams, and configurable stdin.
`CLI < Thor` validates the full configuration before starting the engine.

`Engine` owns registration, PID/group tracking, nonblocking pipes, child reaping,
and lifecycle transitions. A single caller thread drives all mutations. Signal
handlers only set a flag and wake a self-pipe. The loop reaps only its own direct
children, services bounded reads in round-robin order, checks TERM deadlines, and
starts pending replacements once old groups and pipes are finished. Group existence
is tracked independently of leader status; Linux `/proc` distinguishes running
members from orphan zombies awaiting the system reaper.

```ruby
require "foruiman"

env = Foruiman::Env.load(root: Dir.pwd)
engine = Foruiman::Engine.new(procfile: "Procfile", env: env, log_lines: 2_000)
engine.on_event do |event|
  # Types: output, started, restarting, stopping, exited, killed, failed.
  # Fields: type, name, pid, status, record, message.
  # Output records add sequence, stream, time, text, complete.
end

engine.run # install handlers, start all, loop, clean up, restore handlers; returns 0/1
```

For an embedded event loop:

```ruby
begin
  engine.start_all                 # or engine.start("web")
  engine.tick(timeout: 0.03)
  engine.restart("web")            # asynchronous; peers keep running
  engine.stop("worker")            # asynchronous
  engine.start("worker")           # start it again once stopped
  engine.shutdown                  # cancels replacements and requests group cleanup
  engine.tick until engine.finished?
ensure
  engine.close                     # finishes cleanup, closes pipes; safe to repeat
end
```

Call engine methods and event listeners on the driving thread; this is not a
cross-thread messaging API. `run` handles INT/TERM/HUP and restores existing
handlers. An embedding loop that drives `tick` directly owns its signal handling.
`close` disconnects observers so a failed renderer/output consumer cannot prevent
process cleanup. `term_timeout:` exists for deterministic embedded tests; CLI
shutdown always uses five seconds. `state(name)` exposes lifecycle state for
rendering; callers should not mutate it.

Children inherit the configured input stream in plain and embedded use. Before
startup, `manage_input!` gives each child a dedicated pseudo-terminal while the
caller retains the real terminal; `write_input(name, bytes)` forwards input,
`interrupt_process(name)` sends SIGINT to that process group, and `resize_inputs` keeps
the pseudo-terminals sized with the UI. The TUI uses this mode so watch commands
do not see EOF and only the selected process receives interactive input.

The TUI edits commands locally in a bounded `InputLine`, with independent history
for each process, then sends a complete line on Enter. Ctrl-X leaves input mode.
`OutputLine` interprets carriage returns, backspaces, horizontal cursor moves and
line erasure before recording child output; screen controls remain suppressed.

`LogStore` uses per-process `Ring` instances and an aggregate `Ring`, each with O(1)
append, eviction, record replacement, and identity lookup. Immutable `Data` records
are shared. A partial record has one sequence identity; completing it replaces
retained references without re-inserting an already evicted aggregate record.
Sequence order represents first observation, not line completion time. Actual
memory use depends on line length and ring capacity; retained text is bounded by
approximately `(process_count + 1) * capacity * 16 KiB`, plus fixed per-stream and
per-record overhead, with overlap shared between rings.

`Output` bounds each stream, handles partial records, and takes style snapshots.
`ANSI::Decoder` incrementally decodes UTF-8 and suppresses terminal controls;
`ANSI::Styles` keeps bounded independent style properties across rows. A long line
is split into completed records at the size limit.

The TUI loads only in interactive mode. `Terminal` owns raw input and alternate
screen restoration. `Keyboard` decodes fragmented key sequences. `State` stores
selection/help/feedback, and each tab owns a `Viewport` anchored by record identity.
`Renderer` composes framed process navigation, a log pane with a scrollbar, and a
shortcut bar. Its shared log-height calculation keeps paging consistent with the
responsive layout. `Text` measures graphemes through `unicode-display_width` and
clips rows safely. `Theme` uses the terminal's ANSI palette, default foreground and
background, and reverse-video selection, with a monochrome fallback. It does not
read OS theme files or override palette entries; child SGR resets restore terminal
defaults. The header uses the engine's `procfile_path` to identify the loaded file.
`LogFormatter` aligns timestamps, process names, stream markers, and content.
Complete frames reset styles at each row. `Application` connects navigation,
start/stop controls, and selected-child input to the engine and limits drawing to 30 FPS. Resize handling reads current
terminal dimensions each loop; it does not replace an application's WINCH handler.

`Plain` prints completed records and runs to natural completion. `Diagnostics`
keeps internal exceptions separate from process logs, using a private temporary
file in interactive mode and stderr otherwise.
