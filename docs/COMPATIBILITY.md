# Intentional differences from Foreman

Foruiman is a fork-derived MVP, not a drop-in replacement for every Foreman feature.

| Area | Foruiman behavior |
| --- | --- |
| Identity | `foruiman` gem/executable, `Foruiman` namespace, version 0.2.0 |
| Runtime | Ruby 3.2+, POSIX process groups; Linux CI |
| CLI | Thor-based `start [PROCESS]`, `check`, `version`, and `help` |
| Excluded features | No export, scaling/formation, `run`, `.foreman` YAML, custom shutdown timeout, forced color, or timestamp toggle |
| Procfile validation | Reject malformed lines, duplicates, empty commands, and reserved `all`; report line numbers |
| Working directory | Invocation directory unless `-d`; moving a Procfile does not change child cwd |
| Environment | Optional `.env` then explicit env file; parent `ENV` stays untouched |
| Ports | 5000 or `-p`, plus 100 per original entry; `PORT` in the environment is overridden |
| Expansion | `/bin/sh -c` performs shell expansion; no Ruby string substitution |
| Instances | Exactly one instance per entry; `PS=name.1` |
| Failures | Independent process failures; peers keep running |
| Restart | Stop only the affected group, wait for descendants and output, then replace |
| Shutdown | TERM, five-second grace, KILL; track groups after leader exit; restore prior signal handlers |
| Output | Separate stdout/stderr metadata; bounded logs and live partial records |
| Terminal | Tabs, independent scroll/follow, restart, start/stop, and selected-process input controls |
| Plain exit | Wait for all processes; status 0/1; explicit orderly shutdown returns 0 |
| Interactive exit | Remain open after all processes exit; quit explicitly |

Full-screen child terminal applications and background daemonization are outside
this release. Remote process control, persistence across Foruiman sessions,
search, horizontal scrolling, and log export are not provided.
