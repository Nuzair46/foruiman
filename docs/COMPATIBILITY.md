# Intentional differences from Foreman

Foruiman supports common Foreman development workflows. It is not a drop-in
replacement for every Foreman feature.

See the [2026-09-27 compatibility audit](FOREMAN_AUDIT.md) for issue-backed gaps,
direct comparisons with Foreman 0.90.0, and the implementation scope for compatible
development workflows in this TUI. Exporters, the Foreman Ruby API, older
runtimes, and exact legacy presentation are excluded from that work. Its
modernization assessment recommends retaining consistent app-root execution,
strict configuration/env-file validation, and meaningful TUI options. The four
selected improvements are implemented in the unreleased changes below; the audit
preserves the original findings separately from their implementation status.

| Area | Foruiman behavior |
| --- | --- |
| Identity | `foruiman` gem/executable, `Foruiman` namespace, version 0.3.0 |
| Runtime | Ruby 3.2+, POSIX process groups; Linux CI |
| CLI | Thor-based `start [PROCESS]`, `run COMMAND [ARGS...]`, `check`, `version`, and `help` |
| Excluded features | No export, scaling/formation, forced color, or timestamp toggle |
| Procfile validation | Reject malformed lines, duplicates, and empty commands; report line numbers. A process named `all` is valid |
| Working directory | Procfile directory unless `-d`; explicit `-f` and `-e` paths resolve from invocation |
| Environment | Explicit `-e file1,file2` replaces default `.env` loading; later files win; parent `ENV` stays untouched |
| Ports | `-p` or `.foreman` port, then loaded `PORT`, then 5000; plus 100 per original entry. `start PROCESS` validates only that allocation; `check` validates all |
| Expansion | `/bin/sh -c` performs shell expansion; no Ruby string substitution |
| Instances | Exactly one instance per entry; `PS=name.1` |
| Failures | Independent by default; `--exit-on any` stops on any natural exit, `failure` only on an unsuccessful exit |
| Restart | Stop only the affected group, wait for descendants and output, then replace |
| Shutdown | TERM, configurable `-t` grace (default five seconds), KILL; track groups after leader exit; restore prior signal handlers |
| Signals | USR1/USR2 reach every owned process group; applications choose how to handle them. INT/TERM/HUP request orderly shutdown |
| Output | Separate stdout/stderr metadata; bounded logs and live partial records |
| Terminal | Tabs, independent scroll/follow, restart, start/stop, and selected-process input controls; aggregate `0: all` is separate from a process named `all` |
| Plain stdin | Inherited stdin supports pipes, terminal line input, raw reads, and EOF; concurrent readers share the stream |
| Plain exit | Default status 0/1; automatic group shutdown preserves its triggering exit code (128 + signal for a signal exit); explicit orderly shutdown returns 0 |
| Interactive exit | Remain open after all processes exit by default; automatic shutdown policies close the TUI after cleanup |

## Configuration and paths

Like Foreman, `.foreman` is read from the invocation directory. Use long option
names; CLI flags override YAML values. Supported keys are `procfile`, `root`, `env`,
`port`, `timeout`, `dotenv`, `tui`, `log-lines`, and `exit-on` (underscores also work).
Unsupported keys, including `formation`, produce an error instead of being ignored.
YAML object tags and aliases are not supported.

```yaml
procfile: Procfile.dev
port: 3000
timeout: 10
exit-on: any
```

An explicit `-f` path is relative to invocation, even when `-d` is supplied. Without
`-f`, the Procfile is `<root>/Procfile`. Without `-d`, child commands run in the
Procfile's directory. Default `.env` loading follows Foreman's CLI: use the explicit
`-d` directory when supplied, otherwise the invocation directory. An inferred root
from `-f` does not move the default `.env` lookup. Explicit `-e` paths always resolve
from invocation. `--no-dotenv` disables only default `.env` loading.

## One-off commands

`foruiman run bin/rails console` uses the same environment-file rules and passes
stdin, stdout, and stderr directly to the command. No Procfile is required. A
single argument matching a Procfile entry runs that entry's shell command.
Other commands retain their exact argument boundaries. For shell operators, use
`foruiman run sh -c 'command1 && command2'`. Put Foruiman options before the command;
options after the command belong to that command.

`run` replaces Foruiman with the command, preserving signals and exit status. It
does not generate per-process `PORT` or `PS` values or open the TUI.

## Migrating from 0.2

- `-e custom.env` now replaces `.env`. Use `-e .env,custom.env` to retain layering.
- Environment `PORT` now selects the base port. Use `-p 5000` to retain the old default.
- A nested `-f` changes the default child working directory. Add `-d .` to keep
  invocation as the working directory. With `-d app`, an old `-f config/Procfile.dev`
  becomes `-f app/config/Procfile.dev` when that file lives inside `app`.
- A `.foreman` file now supplies defaults. Remove unsupported keys before using it.

Use `--exit-on any` for Foreman's stop-on-first-exit behavior. Intentional TUI
stops and restarts do not trigger that policy. Exact Foreman log formatting and
its Ruby embedding API remain outside compatibility.

Full-screen child terminal applications and background daemonization are outside
this release. Remote process control, persistence across Foruiman sessions,
search, horizontal scrolling, and log export are not provided.
