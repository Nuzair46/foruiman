# Foreman compatibility audit — 2026-09-27

**Scope: Foreman development workflows in a TUI Procfile runner.** The target
is to reuse Procfiles, environment files, applicable `.foreman` settings, and
`start` / `run` commands on Foruiman's supported Ruby/POSIX platforms. The TUI's
independent processes, restarts, input controls, bounded logs, and presentation
remain intentional behavior.

**Original modernization recommendation:** drop three of the nine proposed ports in
full, simplify two others, and treat formation as an optional product feature.
Prioritize signal forwarding, working terminal stdin, and selected-process port
validation; removing the process-name collision with `all` is a useful follow-up.
The table below assesses all nine items individually.

## Implementation status

The selected work is implemented in the unreleased changes:

- **1 — USR1/USR2:** forward to owned process groups in TUI and plain mode, including
  descendants. Signal-aware applications and their waiting shell wrappers stay
  alive; applications without a handler retain the default signal behavior.
- **2 — Plain terminal stdin:** children can read lines, raw bytes, and EOF from
  inherited terminal stdin. Isolated child sessions preserve process-group cleanup.
  This supplies terminal IO, not a new controlling terminal or shell job control.
- **6 — Process named `all`:** process logs, input, and controls are separate from
  the aggregate tab, which keeps shortcut `0`.
- **8 — Selected ports:** validate only the selected process at startup without
  changing its original +100 offset. Whole-app startup and `check` still reject
  invalid allocations before launching children. Positive base ports remain required.

Regression coverage is in [terminal integration](../spec/integration/terminal_spec.rb),
[supervisor integration](../spec/integration/supervisor_spec.rb),
[CLI](../spec/foruiman/cli_spec.rb), and [TUI](../spec/foruiman/tui_spec.rb) specs.
The remaining recommendations retain existing behavior or defer formation.

The baseline measurements and original assessment below describe the pre-fix
version. They are preserved as audit evidence, not claims of current failures.

## Baseline and evidence

- Foruiman: commit `a2f8ebb3a81e4f026284f78c5a1bd615f3f3068e`, version 0.3.0.
- Foreman: installed gem 0.90.0, also the latest version returned by the
  [RubyGems API](https://rubygems.org/api/v1/versions/foreman/latest.json) at audit time.
- Upstream `main`: [`f65ddba83932bd4670e014389d6e27ea1e20b469`](https://github.com/ddollar/foreman/tree/f65ddba83932bd4670e014389d6e27ea1e20b469),
  matching our [recorded import](UPSTREAM.md).
- Execution environment: Linux, MRI Ruby 3.4.5. The existing RSpec suite passed:
  **149 examples, 0 failures**, seed 59308.
- Ran **56 paired CLI probes**, plus **one paired controlling-terminal input
  reproduction**. Each runner used a fresh temporary directory. Probes captured
  stdout, stderr, exit status, termination signal, and timeouts. Some probes
  deliberately used invalid input; this is not a compatibility percentage.
- Retrieved all **442 upstream issues: 53 open, 389 closed**, excluding PRs.
  Screened titles, read all open issue bodies and relevant closed reports, and
  followed selected resolution comments. This is not a claim to have reproduced
  every historical report or read every comment.
- The [Foruiman tracker](https://github.com/Nuzair46/foruiman/issues) contained no
  standalone issues and five closed PRs. [PR #5](https://github.com/Nuzair46/foruiman/pull/5)
  explicitly excluded formation, export, exact log formatting, and USR forwarding.

The [Foreman manual](https://ddollar.github.io/foreman/), pinned implementation,
actual 0.90.0 behavior, and issue history were compared. An open issue is evidence
of a reported problem or requested feature, not proof that it still exists in
0.90.0. Historical Foreman releases also differ from each other.

The runtime comparison uses the [upstream CI matrix](https://github.com/ddollar/foreman/blob/f65ddba83932bd4670e014389d6e27ea1e20b469/.github/workflows/ci.yml)
and [Foreman CLI/engine source](https://github.com/ddollar/foreman/tree/f65ddba83932bd4670e014389d6e27ea1e20b469/lib/foreman),
not an assumption that an unrestricted gemspec proves every Ruby version works.

## Original modernization assessment of the nine items

The goal is a predictable development supervisor with a TUI. Existing useful
workflows matter; reproducing incidental parsing and CLI behavior is optional.
Dropping a port means retaining a documented difference, not claiming parity.

| Original item | Recommendation | Reason and intended contract |
| --- | --- | --- |
| 1. USR1/USR2 forwarding | **Keep the fix.** | These signals currently terminate the shared supervisor instead of reaching children. The TUI does not replace application-defined signal handling. Forward the signals without closing the supervisor; do not reinterpret them as TUI restart shortcuts. [Engine](../lib/foruiman/engine.rb), upstream [#673](https://github.com/ddollar/foreman/issues/673). |
| 2. Terminal stdin in `--no-tui` | **Keep the fix.** | A supported execution mode should allow children to read its controlling terminal. Correct the process-group/input interaction while preserving descendant cleanup. This is a correctness problem, not a legacy UI preference. [Process spawning](../lib/foruiman/process.rb). |
| 3. Formation, scaling and exclusions | **Defer full formation unless it is a product requirement.** | Multiple instances and startup exclusions remain useful capabilities; they are not obsolete just because the interface has tabs. They add instance identity, controls and port allocation work. Existing `start PROCESS` covers a single selected process. TUI stop buttons are not a substitute for excluding a process before it starts. If `-m` is implemented, preserve its counts/exclusions and default-zero semantics rather than silently changing the meaning of an existing flag. Upstream [#398](https://github.com/ddollar/foreman/issues/398). |
| 4. Reusing `.foreman` defaults | **Keep supported settings; drop the proposed permissiveness.** | Continue honoring supported env/root/port/timeout defaults and CLI overrides. There is no need to silently accept export-only `app`, `user`, `log`, `run`, or `template` keys, or treat mistyped/null values as absent. Retain clear validation and document removing unsupported keys during migration. This avoids suggesting a setting has an effect when it does not. [Configuration](../lib/foruiman/configuration.rb). |
| 5. Arbitrary `run` working directory | **Do not port Foreman's special case.** | Keep the current consistent application-root cwd for named and arbitrary commands. `-d` has one meaning, and relative commands work relative to the configured app. Foreman's arbitrary-command invocation-cwd behavior is a migration difference, not a correctness requirement for this product. Use `run -d . ...` when invocation cwd is wanted; this also selects invocation-root default `.env` lookup. An explicit `-e` can preserve a different env-file choice. [CLI](../lib/foruiman/cli.rb). |
| 6. Valid process name `all` | **Keep as a useful design improvement, after correctness fixes.** | An aggregate tab need not prevent a real process from being named `all`. Use a separate internal identity for the aggregate view. This removes an unnecessary UI/name collision without adopting permissive parsing for malformed or duplicate entries. The current explicit reserved-name error remains an acceptable documented migration restriction until changed. [Procfile](../lib/foruiman/procfile.rb). |
| 7. Legacy presentation-option acceptance | **Do not add acceptance-only compatibility flags.** | Do not add `-c`, `--color`, or `--timestamp` switches solely to accept and ignore them. The TUI owns presentation. Keep a clear unsupported-option error; if color/timestamp control is later useful in the plain fallback, implement it as a real feature with documented behavior. |
| 8. Port allocation for selected processes | **Fix selection validation; defer port-zero support.** | `start web -p 65500` should not fail because an unselected worker would receive 65600. Validate selected instances and preserve original offsets. Do not port arbitrary `to_i` coercion. Base port zero is a separate allocation policy: the +100 rule would give the second type 100, so accepting zero is not an automatic-port policy for the whole app. Keep positive-port validation until zero has an explicit use case and defined semantics. [Engine](../lib/foruiman/engine.rb). |
| 9. Environment-file option edge cases | **Do not port permissive list parsing.** | Keep rejecting `-e ''` and `-e custom.env,`. Use the existing `--no-dotenv` to disable default loading, and `-e custom.env` for a nonempty list. `--no-dotenv` still permits explicit `-e` files, including a configured `.foreman` env setting; remove that explicit setting too if the intent is to load no file. Preserve precedence and valid multiple-file support. [Configuration](../lib/foruiman/configuration.rb). |

This leaves **three correctness fixes**, **one process-name improvement**, and
**formation as a separate optional feature**. The other recommendations preserve
current behavior and require clear migration documentation, not porting code.

## Differences excluded from this version's compatibility work

The wider exclusions below remain in addition to the recommendations above.
They do not imply that missing features exist or that an observed difference was
incorrect.

| Exclude | Treatment |
| --- | --- |
| Exporters and custom export templates | No systemd, upstart, launchd, runit, inittab, bluepill, daemon or supervisord export work. Keep clear errors for unsupported config keys and document removing them during migration. |
| Ruby embedding/extension API and old executable identity | Keep the `Foruiman` namespace and `foruiman` gem/executable. No `Foreman::*` adapter, replacement gem identity, or requirement to satisfy existing `gem list -i foreman` checks. Changing `bin/dev` to invoke Foruiman is part of migration. |
| Older Ruby and native Windows support | Keep the existing Ruby 3.2+ and POSIX scope. Platform expansion is separate work. Linux tests do not establish macOS correctness; verify any platform-specific claim separately. |
| Exact log format, raw-log transport and cross-stream ordering | Tabs, timestamps, stream labels, lifecycle text, colors and separate stdout/stderr metadata can differ. TUI control-sequence interpretation, bounded records and long-line splitting are intentional. Byte-identical plain output, raw JSON transport and exact merged ordering are not compatibility goals for this version. |
| Default stop-on-first-exit and aggregate exit status | Keep independent processes, isolated restarts, remaining open after children exit, aggregate 0/1 completion status, and explicit user quit returning 0. Retain the existing `--exit-on any` option and verify its documented triggering-code behavior. There is no unique Foreman-style triggering process under the independent default. |
| No-argument help, `tree`, and exact diagnostics | Keep default `start`, full-screen interaction, shortcuts, and current help/error wording and streams. Do not restore `tree` solely for Thor parity. |
| Permissive parsing and `check` behavior | Keep clear validation of malformed/duplicate/empty entries and the broader environment/port checks documented for `check`. The `all` name collision is resolved without relaxing those checks. |
| Upstream expansion and signal-status quirks | Keep shell quoting/variable boundaries and direct `run` exec. Do not copy substring replacement that expands single-quoted variables or corrupts `$FOOBAR`, return success for a signaled command just because upstream does, or reject arbitrary `run` solely because an unrelated Procfile is empty. |
| Production init, escaped daemons and unrelated feature requests | No PID 1 init guarantee, daemon management, remote sessions, automatic reload/sequencing, or features belonging to Puppet Foreman/node-foreman. Keep cleanup of owned development process groups. |

## Important details from the reproductions

**Terminal input is a real regression, independent of the TUI.** The stdin
reproduction used a controlling terminal created by `PTY.spawn`, not just a PTY
file descriptor. The child wrote `READY`, then called `STDIN.gets`. Foreman
printed `GOT:hello` and exited normally. Foruiman's background process group
stopped on terminal input; after two seconds the harness requested shutdown and
the configured timeout escalated to KILL. Existing terminal specs mostly use
`PTY.open` plus `Process.spawn`, which does not establish that slave as the
child's controlling terminal. Add a controlling-terminal regression test before
changing process group or input handling.

**Excluded evidence: exact signal exit parity.** For a direct
`ruby child.rb` that sends itself TERM, Foreman returned 0. Foruiman's extra shell
reported 143 internally and the default policy returned 1. For `run ruby
child.rb`, Foreman returned 0 while Foruiman itself was terminated by TERM
(`Process::Status#termsig == 15`). A shell may display 143 for a signaled command,
but wait-status consumers can distinguish it from an ordinary exit 143. Foreman
0.90.0's treatment of a directly signaled child is an upstream quirk, not a
recommendation to hide failures.

**Excluded evidence: upstream command-expansion quirks.** With
`.env` containing `FOO=hello` and `FOOBAR=world`:

| Procfile command | Foreman child output | Foruiman child output |
| --- | --- | --- |
| `printf '%s\n' '$FOO'` | `hello` | `$FOO` |
| `printf '%s\n' "$FOOBAR"` | `helloBAR` | `world` |

With `FOO=$(printf expanded)` and `printf '%s\n' "$FOO"`, Foreman printed
`expanded`; Foruiman printed the literal `$(printf expanded)`. Foruiman's normal
shell semantics are retained for this TUI scope; this difference is documented
and is not an implementation task.

**Port limits can reject an otherwise usable selected process.** This is not
only about invalid port strings: 65500 is valid for `web`, but validation of an
unselected second entry rejects the entire command. Formation implementation
would need to allocate selected instances without renumbering their original
Procfile positions. The selection-validation bug can be fixed independently of
formation support.

**No signal orphan was observed in the dedicated USR1 cleanup probe.** The
supervisor still terminated instead of forwarding. Report that confirmed
failure without assuming every such termination leaves a live child behind.

## Minimal reproductions

Use a fresh directory for each fixture. Run the listed arguments with Foreman
0.90.0 and then Foruiman 0.3.0. Use `--no-tui` on Foruiman when inspecting a short-lived command without
the persistent TUI. Compare process behavior, cwd, environment and argument
acceptance. These reproduce the original findings, including differences now
recommended for retention; they are not all failing acceptance criteria. Exact
log text and aggregate status under independent supervision are outside the
scoped comparison.

| Fixture | Command arguments | Observed difference |
| --- | --- | --- |
| `Procfile`: `web: echo hello` | `start -m web=2` | Two instances versus unknown switch. |
| Same Procfile; `.foreman`: `app: demo` | `start` | Runs versus unsupported config key. |
| Create empty `app/` directory; no Procfile | `run -d app ruby -e 'puts Dir.pwd'` | Invocation directory versus `app/`. |
| `Procfile`: `all: echo hello` | `start` | Runs versus reserved-name error. |
| `Procfile`: `web: echo hello` | `start -c` or `start --no-timestamp` | Accepted versus unknown switch. |
| `Procfile`: `web: echo hello`, then `worker: echo worker` on the next line | `start web -p 65500` | Runs web versus rejecting an unselected worker's port. |
| `.env`: `FOO=file`, with inherited `FOO=parent` | `run -e '' ruby -e 'puts ENV["FOO"]'` | Prints parent versus rejecting empty env option. |

For terminal input, create `reader.rb`:

```ruby
STDOUT.sync = true
puts "READY"
puts "GOT:#{STDIN.gets}"
```

Use `web: ruby reader.rb` as the Procfile. In a real foreground terminal, run
`foreman start -t 0.1`, type `hello` and Enter after READY. Repeat with
`foruiman start --no-tui -t 0.1`. The first prints `GOT:hello`; the second stops
the reader. Ctrl-C requests shutdown. A pipe-fed stdin test will not reproduce
this controlling-terminal problem.

For signal forwarding, create `signals.rb`:

```ruby
STDOUT.sync = true
Signal.trap(:USR1) { puts "RECEIVED USR1" }
Signal.trap(:USR2) { puts "RECEIVED USR2" }
puts "READY"
sleep
```

Use `web: ruby signals.rb` as the Procfile. After READY, send `kill -USR1 PID`
from another terminal to the **supervisor's** PID. Foreman prints the forwarded
message and remains running; Foruiman terminates. Repeat in a fresh invocation
for USR2. Terminate a surviving Foreman supervisor normally after observing it.

## Behaviors already supported

The paired probes confirmed common environment precedence: inherited variables
are available, `.env` overrides them, explicit `-e first,last` replaces the
default `.env`, and later explicit files win. CLI port overrides `.foreman`,
loaded `PORT` and inherited `PORT`. Selecting the second process retains its
original +100 port offset and `PS=worker.1`.

Nested `-f` moves the supervised/named-command working directory while default
`.env` still comes from invocation unless `-d` is supplied. Named `run` uses the
Procfile root. Arbitrary `run` works without a Procfile, preserves argument
boundaries and child switches, and preserves ordinary nonzero exit codes.

The existing passing suite additionally covers quoted/escaped environment
values, CRLF, missing explicit environment files, stdin pipes, shutdown timeout
escalation, bounded log retention, cleanup of descendants in managed groups,
isolated restarts, and TUI terminal restoration. These are useful tests, but
they assert Foruiman's own contract; passing them is not a Foreman conformance
certificate.

## Issue-history conclusions

The most useful closed reports are [#673](https://github.com/ddollar/foreman/issues/673)
(USR forwarding), [#676](https://github.com/ddollar/foreman/issues/676)
(context for our intentional lifetime difference), [#398](https://github.com/ddollar/foreman/issues/398)
(formation defaults), [#274](https://github.com/ddollar/foreman/issues/274) and
[#275](https://github.com/ddollar/foreman/issues/275) (one-off argument handling),
[#271](https://github.com/ddollar/foreman/issues/271) (run without a Procfile),
[#230](https://github.com/ddollar/foreman/issues/230) (named run), and
[#489](https://github.com/ddollar/foreman/issues/489) (interactive run signals).
They identify relevant command/process regressions and intentional differences;
the modernization assessment above determines which observations warrant work.

Do not restore historical failures as features. Unknown process selection
([#565](https://github.com/ddollar/foreman/issues/565),
[#568](https://github.com/ddollar/foreman/issues/568)) hung in the 0.90.0 probe
until the harness sent TERM; Foruiman's immediate error is an improvement.
Foreman's environment interpolation changed between historical versions
([#561](https://github.com/ddollar/foreman/issues/561)), so compatibility with
every Foreman release cannot be inferred from matching 0.90.0.

The following accounts for all 53 currently open issues. Grouping describes
their relevance; it does not claim each reported application failure is fixed.

| Open upstream issues | Assessment for Foruiman |
| --- | --- |
| [#779](https://github.com/ddollar/foreman/issues/779), [#775](https://github.com/ddollar/foreman/issues/775), [#768](https://github.com/ddollar/foreman/issues/768), [#708](https://github.com/ddollar/foreman/issues/708) | Child/descendant cleanup. Managed process-group cleanup is tested; escaped sessions, Spring daemons and exact reported applications remain unverified. Closed [#810](https://github.com/ddollar/foreman/issues/810) is a related npx case whose reporter used an exec wrapper. |
| [#681](https://github.com/ddollar/foreman/issues/681) | Excluded: successful child exit stopping peers is Foreman behavior. Preserve Foruiman's independent default. |
| [#703](https://github.com/ddollar/foreman/issues/703) | Debugger echo/input: Foruiman offers selected-process TUI input, but the plain-mode controlling-terminal failure remains. |
| [#808](https://github.com/ddollar/foreman/issues/808), [#750](https://github.com/ddollar/foreman/issues/750), [#754](https://github.com/ddollar/foreman/issues/754) | Logging requests. Exact presentation/raw logging is excluded. Acceptance-only color/timestamp aliases are also not recommended. Real display controls can be added independently if useful. |
| [#702](https://github.com/ddollar/foreman/issues/702), [#755](https://github.com/ddollar/foreman/issues/755) | Environment precedence and physical multiline `.env` values. Current parsers share Foreman's limitations. Dotenv compatibility is a different target; do not silently reverse precedence or assume full dotenv syntax. Escaped `\n` in double quotes is supported. |
| [#784](https://github.com/ddollar/foreman/issues/784), [#751](https://github.com/ddollar/foreman/issues/751), [#715](https://github.com/ddollar/foreman/issues/715), [#714](https://github.com/ddollar/foreman/issues/714) | PORT defaults, `.foreman` configuration and offsets. Common semantics match; fix selected-process validation and treat scaling as an optional feature. Do not change the default 5000 to resolve an OS-specific port conflict while claiming identical defaults. |
| [#705](https://github.com/ddollar/foreman/issues/705) | Optional product feature: multiple worker instances require formation or an equivalent explicit design. Historical `-c` concurrency syntax in the report is not the 0.90.0 contract; use `-m` if Foreman formation is implemented. |
| [#794](https://github.com/ddollar/foreman/issues/794), [#709](https://github.com/ddollar/foreman/issues/709), [#704](https://github.com/ddollar/foreman/issues/704), [#668](https://github.com/ddollar/foreman/issues/668), [#695](https://github.com/ddollar/foreman/issues/695) | Excluded: exporters and deployment templates. Their absence is not a blocker for this TUI scope. The old `File.exists?` failure in #794 was already fixed in the baseline source despite the issue remaining open. |
| [#797](https://github.com/ddollar/foreman/issues/797), [#793](https://github.com/ddollar/foreman/issues/793), [#789](https://github.com/ddollar/foreman/issues/789), [#733](https://github.com/ddollar/foreman/issues/733) | Excluded: native Windows. Foruiman remains POSIX-only; no Windows compatibility or fix is claimed. |
| [#759](https://github.com/ddollar/foreman/issues/759) | Windows DSC export is an upstream feature request, not a supported Foreman format that must be copied. |
| [#766](https://github.com/ddollar/foreman/issues/766), [#764](https://github.com/ddollar/foreman/issues/764), [#748](https://github.com/ddollar/foreman/issues/748) | Default-start UX is intentional and excluded from parity. Normal `start -f` path/option handling remains applicable and covered. |
| [#762](https://github.com/ddollar/foreman/issues/762), [#707](https://github.com/ddollar/foreman/issues/707) | Environment usage questions. Parent env is inherited; explicit files and their overriding precedence must stay consistent. |
| [#679](https://github.com/ddollar/foreman/issues/679), [#684](https://github.com/ddollar/foreman/issues/684), [#746](https://github.com/ddollar/foreman/issues/746), [#699](https://github.com/ddollar/foreman/issues/699), [#713](https://github.com/ddollar/foreman/issues/713) | Requests/questions about reload, code watching, sequencing, conditional Procfiles and remote log views. They are not existing Foreman requirements. HUP means shutdown in both implementations. Foruiman's manual restarts do not imply automatic reload support. |
| [#796](https://github.com/ddollar/foreman/issues/796), [#786](https://github.com/ddollar/foreman/issues/786), [#782](https://github.com/ddollar/foreman/issues/782), [#693](https://github.com/ddollar/foreman/issues/693), [#731](https://github.com/ddollar/foreman/issues/731), [#645](https://github.com/ddollar/foreman/issues/645), [#700](https://github.com/ddollar/foreman/issues/700) | App-specific failures, startup/output/shutdown reports, or insufficient reproductions. No verified Foreman conformance change can be concluded from their titles alone. Real Rails/Yarn/Redis/Sidekiq fixtures remain useful validation work. |
| [#752](https://github.com/ddollar/foreman/issues/752), [#688](https://github.com/ddollar/foreman/issues/688) | Historical Thor dependency failures. Foreman 0.90.0 now depends on Thor ~>1.4; Foruiman allows >=1.3,<2. Exact Thor behavior should be pinned in differential tests. |
| [#811](https://github.com/ddollar/foreman/issues/811), [#806](https://github.com/ddollar/foreman/issues/806), [#783](https://github.com/ddollar/foreman/issues/783), [#778](https://github.com/ddollar/foreman/issues/778), [#776](https://github.com/ddollar/foreman/issues/776), [#767](https://github.com/ddollar/foreman/issues/767) | Project links, another fork, release naming and style tooling. No runtime compatibility requirement. |
| [#736](https://github.com/ddollar/foreman/issues/736), [#718](https://github.com/ddollar/foreman/issues/718) | Reports concern Puppet's Foreman or node-foreman, not this Ruby CLI. |

## Recommended implementation order

1. **Fix process-control correctness.** Forward USR1/USR2 and fix real
   controlling-terminal stdin in `--no-tui`. Preserve isolated restarts,
   process-group cleanup, user quit, and optional shutdown policies.
2. **Fix selected-process port validation.** Check allocations for selected
   processes without renumbering original entry offsets. This does not require
   formation or port-zero support.
3. **Remove the process-name/UI collision if desired.** Give the aggregate tab
   its own identity so a process called `all` can work. Keep strict validation
   of malformed and duplicate entries.
4. **Consider formation independently.** Add multi-instance processes and
   exclusions only as an explicit capability. If exposing Foreman's `-m`, retain
   its semantics and test per-instance ports, `PS`, logs and controls. Until
   then, keep a clear unsupported-option error.
5. **Document retained differences.** Keep consistent app-root `run`, supported
   `.foreman` defaults with strict validation, explicit env-file syntax,
   positive base ports and the TUI's presentation contract. Give migration
   examples instead of adding silent no-op flags or copying parser quirks.

Test the correctness fixes with real controlling terminals, signal handlers,
cleanup checks and selected-process fixtures. Compare with pinned Foreman where
behavior is deliberately shared; test retained differences against Foruiman's
own documented contract. No default-lifetime reversal, exporter, API shim or
legacy rendering layer is needed.

With these modernization choices, describe the product as **a modern alternative
to Foreman for Procfile development workflows**. List the supported shared
workflows and migration differences. An unqualified drop-in claim would conflict
with the intentionally retained command/configuration differences. See
[COMPATIBILITY.md](COMPATIBILITY.md) for current implemented behavior.
