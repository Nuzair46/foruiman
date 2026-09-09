# Inputs and implementation defaults

The implementation workspace was empty. The RFC referenced by the supplied plan,
its requested file list, and earlier preference selections were not present. The
supplied Foreman-based MVP plan is the implementation contract available here.
The missing RFC was requested during implementation; these choices fill the gaps:

- Default command `start`; also `start PROCESS`, `check`, `version`, `help`.
- Foreman's `-f`, `-d`, `-e`, `-p` aliases; `--log-lines`, `--no-tui`, `--no-dotenv`.
- Default capacity 10,000 records per ring.
- Process tabs in entry order, then `all`; select `all` initially.
- `all` reserved as a process name to avoid an ambiguous aggregate tab.
- Vim-style and arrow navigation, digits, `f`, Space, `r`/`R`, `s`/`S`, `?`, `q`.
- Generated `PS=name.1`, as in Foreman; no other generated variables.
- Relative file paths resolved against invocation directory or explicit `-d`.
- Header whitespace after a Procfile colon is a separator; command-internal and
  trailing whitespace is preserved.
- 30 FPS maximum; 16 KiB records; 64 KiB total read budget per event-loop iteration.
- No public repository URL is invented for the unpublished Foruiman project.

See README for the actual public interface. These defaults can be reconciled with
the original RFC when it becomes available; missing requirements are not claimed
as verified.
