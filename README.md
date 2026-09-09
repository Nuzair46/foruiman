# Foruiman

A Procfile runner with process tabs, bounded logs, scrolling, and isolated restarts.
Foruiman 0.1.2 is derived from [David Dollar's Foreman](https://github.com/ddollar/foreman),
at commit [`f65ddba83932bd4670e014389d6e27ea1e20b469`](https://github.com/ddollar/foreman/commit/f65ddba83932bd4670e014389d6e27ea1e20b469).
The MIT license and attribution are preserved. See [provenance](docs/UPSTREAM.md)
and [intentional compatibility differences](docs/COMPATIBILITY.md).

Requires Ruby 3.2+ and a POSIX system with `/bin/sh` and process groups. Linux is
covered by CI on Ruby 3.2, 3.3, 3.4, and 4.0. Native Windows is unsupported; use WSL.

## Install from this checkout

```sh
bundle install
gem build foruiman.gemspec
gem install --local ./foruiman-0.1.2.gem
```

Or run directly with `bundle exec ruby bin/foruiman`. This checkout does not publish
a gem or create a hosted fork.

## Run

Create a `Procfile`:

```procfile
web: bundle exec rails server -p "$PORT"
worker: bundle exec sidekiq
css: yarn build:css --watch
```

```sh
foruiman                         # default command: start
foruiman start -f Procfile.dev
foruiman start web               # one entry, with its original allocated port
foruiman start --no-tui          # stream logs
foruiman check                   # validate everything without spawning
foruiman --version
foruiman help start
```

Processes run independently. A failed process stays visible and does not stop its
peers. Restart a selected process with `r`; its old process group is stopped and
its remaining output drained before the replacement starts. Logs survive restarts.
The terminal interface stays open after all processes exit.

When either stdin or stdout is not a TTY, Foruiman automatically streams plain
logs. Each completed record includes a timestamp, process name, and stream:

```text
12:30:01 web [stdout] | Listening on port 5000
12:30:02 worker [stderr] | Connection refused
```

Plain mode exits after all children and owned groups finish: `0` if all succeeded,
`1` if any failed. An explicit orderly shutdown through `q`, Ctrl-C, SIGINT,
SIGTERM, or SIGHUP returns `0`, including when TERM needs escalation to KILL.
Validation and internal failures return `1`.

## Options

| Option | Default | Meaning |
| --- | --- | --- |
| `-f`, `--procfile FILE` | `Procfile` | Procfile, resolved against the working directory |
| `-d`, `--root DIR` | Invocation directory | Child working directory and base for relative file paths |
| `-e`, `--env FILE` | None | Explicit environment file, loaded after optional `.env` |
| `--no-dotenv` | Load `.env` if present | Skip automatic `.env` loading |
| `-p`, `--port PORT` | `5000` | First process port; each following entry adds 100 |
| `--log-lines N` | `10000` | Positive record capacity for each process and for `all` |
| `--no-tui` | Use TUI when both streams are TTYs | Force plain output (`start` only) |

Ports must fit `1..65535`, including the last allocation. Invalid ports, capacities,
entries, duplicate names, missing explicit files, and empty Procfiles fail before
any process is started. Names use letters, digits, `_` and `-`; `all` is reserved.
Comments and blank lines are ignored. Whitespace following the colon is the entry
separator; whitespace inside and at the end of commands is preserved. Diagnostics
include the filename and line number.

Environment precedence is inherited environment → optional `.env` in the working
directory → explicit env file → generated `PORT` and `PS`. For example, the second
entry named `worker` gets `PORT=5100` and `PS=worker.1`. An inherited or file-defined
`PORT` does not change the base port. Parent `ENV` is never modified.

Env files use Foreman's assignment rules: `KEY=value`, `KEY='literal'`, and
`KEY="escaped value"`. Double-quoted `\n` becomes a newline and backslash escapes
are removed. Unquoted values are preserved, including spaces and `#`. Blank lines,
comments, and lines that are not assignments are ignored. No `export`, interpolation,
command substitution, or sourcing takes place in env files. Shell expansion happens
when the Procfile command runs through `/bin/sh -c`.

## Terminal interface

![Foruiman terminal interface with sample logs](docs/terminal-preview.png)

The preview uses an example terminal palette; colors follow your own theme.

The interface follows your terminal's theme, with a layout inspired by btop and
Omarchy: framed process tabs, a highlighted selection,
consistent process colors, red stderr, amber lifecycle markers, and a compact
shortcut bar. The selected process shows its state and PID; wider layouts also
show its exit code or allocated port. `LIVE` indicates an active process stream;
`FOLLOW` remains available after exit, and `PAUSED` marks a scrolled viewport.
A scrollbar and retained-line range show where you are in the log history.
The header shows the active Procfile, including paths selected with `-f`, relative
to the working directory. Narrow layouts prioritize the filename over the project
name and shorten long paths.

The layout adapts to smaller terminals by removing extra frames and metadata
before reducing the log area. Glyphs identify process states (`●` running, `↻`
restarting, `✓` exited, `×` failed, `■` stopped), navigation, and log follow mode.
No special font or Nerd Font is required.
Colors come from the terminal's ANSI palette and default foreground/background;
Foruiman does not impose RGB colors or a background. On a setup such as Omarchy,
the terminal's global theme supplies these colors automatically. Theme changes
apply live when the terminal updates its palette. Reverse video highlights the
selected tab using the terminal's own foreground/background, including light themes.
Set `NO_COLOR=1` for monochrome; `TERM=dumb` also disables interface colors.
Selection and bold emphasis remain visible in monochrome. Child ANSI styles,
including explicit RGB colors, remain supported and reset to terminal defaults.

A static preview is available without starting any processes:

```sh
ruby -Ilib script/preview.rb 116 30
ruby -Ilib script/preview.rb 80 24 web
ruby -Ilib script/preview.rb 116 30 help
```

## Keyboard

Process tabs follow Procfile order; `all` is last and selected initially. The
selected tab stays visible when there are more tabs than fit across the screen.

| Key | Action |
| --- | --- |
| Tab / Shift-Tab, Left / Right, `h` / `l` | Previous or next tab |
| `1`–`9` | Select a process tab |
| `0` | Select `all` |
| Up / Down, `k` / `j` | Scroll a line |
| PageUp / PageDown, Ctrl-U / Ctrl-D | Scroll a page |
| Home / `g` | Oldest retained record |
| End / `G` / `f` | Follow newest output |
| Space | Toggle follow |
| `r` | Restart selected process; on `all`, restart every process |
| `R` | Restart every process from any tab |
| `s` / `S` | Stop selected process / all processes |
| `?` / Escape | Toggle help / close help |
| `q` / Ctrl-C | Shut down and quit |

Each tab keeps its own scroll position and follow setting. Scrolling pauses follow;
new output does not move the view. Eviction or a resize clamps the view to retained
records. On the `all` tab, `r` restarts all processes. To stop processes from that
tab, use `S`; lowercase `s` requires a selected process.

The UI shows lifecycle status, PID, exit status, and shutdown progress. It redraws
at up to approximately 30 FPS, truncates long rows horizontally, and restores the
prior terminal input mode, cursor, and screen after normal exit or an exception.
Very small terminals show a compact message; shortcuts continue working.

## Logs and cleanup

Both per-process rings and the aggregate ring have independent limits. Immutable
records are shared between rings and have globally increasing sequence identities.
Partial output appears live in the TUI and keeps its identity when completed.
Plain mode emits at newline or EOF; records reaching the 16 KiB limit are also
completed and emitted. Each stream has bounded pending data; reads are budgeted
per event-loop iteration. Old output cannot grow retention without bound.

Supported SGR styles (colors, intensity, italics, underline, blink, inverse, conceal,
and strike) are retained in the TUI. Cursor/screen controls, OSC, DCS, and clipboard
sequences are suppressed. UTF-8 and escape sequences may arrive in fragments.
Invalid bytes become replacement characters. Carriage returns are ignored; tabs
become four spaces. Styles reset at row boundaries, and each row carries the stream's
style snapshot. Unicode width uses `unicode-display_width`, treating combined emoji
as two cells. Plain output strips styles.

Every entry has its own process group, separate stdout/stderr pipes, and `/dev/null`
stdin. Child programs cannot interact with the terminal. Shutdown cancels pending
restarts, sends TERM to all owned groups, escalates after five seconds, drains pipes,
and reaps direct children. Descendants are tracked even when their group leader
exits. On Linux, orphan zombies awaiting the system reaper do not hold shutdown open;
they are no longer running. Processes deliberately escaping their group by daemonizing
are outside v1. Run servers in the foreground.

Internal exception details go to stderr in plain mode. Interactive exceptions go
to a private `foruiman-*.log` temporary file (mode 0600); the restored terminal shows
its path. Normal child output never goes to this diagnostic file.

See [Rails usage](docs/RAILS.md), [supervisor API and architecture](docs/ARCHITECTURE.md),
and [implementation assumptions](docs/ASSUMPTIONS.md).

## Development

```sh
bundle install
bundle exec rspec
bundle exec rubocop
gem build foruiman.gemspec
bundle exec ruby script/smoke_gem.rb
```

The suite includes adapted upstream parser and environment cases, Ruby subprocess
fixtures, bounded-output tests, fake-terminal tests, and real PTYs. Process tests
clean up their fixtures even when assertions fail. Nothing here requires Rails.
