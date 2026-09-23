# Using Foruiman with Rails

Install the locally built Foruiman gem as a development tool using the README's
instructions. Keep it outside the Rails application's Gemfile when using a global
development-tool installation. The Rails processes can still run under `bundle exec`.

A typical `Procfile.dev`:

```procfile
web: bin/rails server -p "$PORT"
worker: bundle exec sidekiq
css: yarn build:css --watch
```

Include only entries used by your app. For a Vite application, replace the CSS entry
with your project's foreground Vite command, for example `vite: bin/vite dev`.
Use your app's existing port configuration for tools that do not read `PORT`.

An optional `.env` in the Rails project root:

```dotenv
RAILS_ENV=development
REDIS_URL=redis://localhost:6379/0
```

Keep secrets out of version control. Foruiman reads this file as assignments; it
does not source it as a shell script.

From the Rails root:

```sh
foruiman start -f Procfile.dev
foruiman start -f Procfile.dev -p 3000
```

The second example assigns 3000 to `web`, 3100 to `worker`, and 3200 to `css`.
Only programs that consume their generated `PORT` use those values. The base port
comes from `-p` or `.foreman`, then `PORT` in the loaded environment, then 5000.

Run a Rails command using the same environment without starting the Procfile:

```sh
foruiman run bin/rails console
foruiman run -e .env,.env.local bin/rails db:migrate
```

Explicit `-e` files replace default `.env` loading, so include `.env` in the list
when layering local overrides. For Foreman-style group shutdown and a longer grace
period, use `foruiman start -f Procfile.dev --exit-on any -t 10`.

An optional `bin/dev`:

```sh
#!/bin/sh
exec foruiman start -f Procfile.dev "$@"
```

Select the web tab and press `r` to restart Rails without interrupting the worker
or asset watcher. On the `all` tab, `r` restarts all entries; `R` does so from any
tab. Default watch modes stay running because their stdin remains open. When Rails
stops in Pry, Byebug or IRB, select `web` and press `i`. Edit commands in the input
bar and press Enter to send them. Up/Down recall history, Left/Right move the
cursor, and Ctrl-X returns to Foruiman. Ctrl-C interrupts the selected process;
debugger tab completion is not forwarded. Press `s` to stop the selected entry
and press it again to start it; `s` on `all` stops every entry. The header shows the
active Procfile. `q` or Ctrl-C stops all owned process
groups, including grandchildren, before returning to the shell.

Redirect output with `foruiman start -f Procfile.dev > development.log` to use plain
mode. A failed worker will not stop Rails; plain mode finishes only after every
entry exits or Foruiman receives a shutdown signal.
