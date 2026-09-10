# Changelog

## Unreleased

## 0.2.0

- Keep child stdin open so default watcher modes continue running.
- Add per-process TTY input from the TUI: select a process, press `i`, and use
  Ctrl-X to return to Foruiman. Ctrl-C interrupts the attached process group.
- Add a command input bar with local backspace, cursor editing and per-process
  history. Interpret debugger redraws instead of appending repeated prompts.
- Make `s` stop a running selected process and start it again once stopped,
  without affecting peers. Use clear `▶` running and `■` stopped glyphs.
- Make `s` on the `all` tab stop every process, matching the scope of `r`.

- Test Ruby 3.2, 3.3, 3.4, and 4.0 in a reusable CI workflow and keep the
  development dependency set compatible with Ruby 3.2.
- Add a tag-driven RubyGems trusted-publishing workflow gated by the full CI suite.
- Make renderer row-width checks independent of the runner's terminal settings.

## 0.1.2

- Fix lowercase `r` on the `all` tab to restart every process; keep `R` available
  from any tab and make the footer describe the selected restart scope.
- Show the active Procfile in the header, including custom paths and working
  directories, with filename priority in narrow terminals.
- Follow the terminal's global theme through its ANSI palette and default
  background. Use reverse-video selection for light, dark, and monochrome themes.
- Verify group restarts with real keyboard input and process cleanup, and cover
  Procfile titles, theme inheritance, and preserved child colors.

## 0.1.1

- Redesign the TUI with a forest palette, framed process navigation, selected-tab
  backgrounds, status colors, aligned log columns, a scrollbar, and grouped help.
- Support truecolor, 256 colors, and `NO_COLOR`; preserve child ANSI styles without
  letting resets overwrite the interface background.
- Adapt chrome and log metadata to terminal size, keep selected tabs visible,
  and use the actual visible log height for scrolling and paging.
- Include a static preview fixture and expand color, layout, and PTY coverage.

## 0.1.0

- Fork-derived MVP based on Foreman `f65ddba83932bd4670e014389d6e27ea1e20b469`.
- Strict Procfiles, layered environments, and validated port allocation.
- Independent process supervision, bounded log rings, and asynchronous restarts.
- Terminal tabs, scrolling, Unicode-aware rows, and exception-safe restoration.
- Automatic plain mode and process-group cleanup with TERM/KILL escalation.
