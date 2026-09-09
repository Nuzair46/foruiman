# frozen_string_literal: true

# A static design fixture. No child processes are started.
# ruby -Ilib script/preview.rb [columns] [rows] [all|web|worker|assets|jobs|help]
require "foruiman"
require "foruiman/tui/renderer"
require "foruiman/tui/state"

PreviewEngine = Struct.new(:root, :procfile_path, :processes, :logs, keyword_init: true) do
  def process_names
    processes.map(&:name)
  end

  def state(name)
    processes.find { |entry| entry.name == name }
  end

  def shutting_down?
    false
  end
end

columns = Integer(ARGV.fetch(0, "116"))
rows = Integer(ARGV.fetch(1, "30"))
selection = ARGV.fetch(2, "all")
names = %w[web worker assets jobs]
processes = names.each_with_index.map do |name, index|
  Foruiman::Engine::State.new(name: name, pid: 28_410 + index, port: 3000 + (index * 100),
                              generation: 1, status: name == "jobs" ? :failed : :running)
end
logs = Foruiman::LogStore.new(names, capacity: 10_000)
entries = [
  ["web", :lifecycle, "--- started with pid 28410 (generation 1) ---"],
  ["worker", :lifecycle, "--- started with pid 28411 (generation 1) ---"],
  ["assets", :lifecycle, "--- started with pid 28412 (generation 1) ---"],
  ["web", :stdout, "Puma starting in single mode…"],
  ["web", :stdout, "* Listening on http://127.0.0.1:3000"],
  ["worker", :stdout, "Connected to Redis at redis://localhost:6379/0"],
  ["assets", :stdout, "\e[1mVITE\e[0m v6.2.0  ready in \e[32m182 ms\e[0m"],
  ["assets", :stdout, "➜  Local: http://localhost:3200/"],
  ["web", :stdout, 'Started GET "/dashboard" for 127.0.0.1'],
  ["web", :stdout, "Processing by DashboardController#index as HTML"],
  ["web", :stdout, "  User Load (0.4ms)  SELECT users.* FROM users WHERE id = 1"],
  ["worker", :stdout, "DailyDigestJob started  jid=9b8a2c  queue=default"],
  ["web", :stdout, "  Rendered dashboard/index.html.erb (Duration: 12.8ms)"],
  ["web", :stdout, "Completed \e[32m200 OK\e[0m in 34ms (Views: 18.2ms | ActiveRecord: 1.4ms)"],
  ["worker", :stdout, "DailyDigestJob done  elapsed=0.126s"],
  ["jobs", :stderr, "Connection refused — connect(2) for 127.0.0.1:5433"],
  ["jobs", :stderr, "PG::ConnectionBad: could not connect to the background database"],
  ["jobs", :lifecycle, "--- exited with code 1 ---"],
  ["assets", :stdout, "[vite] hmr update /app/frontend/components/dashboard.tsx"],
  ["web", :stdout, 'Started GET "/api/projects" for 127.0.0.1'],
  ["web", :stdout, "  Project Load (0.8ms)  SELECT projects.* ORDER BY updated_at DESC"],
  ["web", :stdout, "Completed \e[32m200 OK\e[0m in 8ms (ActiveRecord: 0.8ms)"],
  ["worker", :stdout, "SyncProjectJob started  jid=31d8f0  queue=default"],
  ["worker", :stdout, "Synced 24 projects  elapsed=0.842s"],
  ["assets", :stdout, "[vite] page reload app/views/layouts/application.html.erb"],
  ["web", :stdout, "Completed \e[32m200 OK\e[0m in 21ms (Views: 12.1ms | ActiveRecord: 2.3ms)"],
  ["worker", :stdout, "Waiting for jobs…"]
]
entries.each_with_index do |(name, stream, text), index|
  record = logs.write(name: name, stream: stream, pid: processes.find { |entry| entry.name == name }.pid,
                      text: text, complete: true)
  record = record.with(time: Time.utc(2026, 9, 9, 14, 32, index).freeze)
  logs[name].replace(record)
  logs.all.replace(record)
end
engine = PreviewEngine.new(root: "/work/atlas", procfile_path: "/work/atlas/Procfile.dev", processes: processes,
                           logs: logs)
state = Foruiman::TUI::State.new(names)
state.select(names.index(selection)) if names.include?(selection)
state.help = selection == "help"
print Foruiman::TUI::Renderer.new.render(state, engine, rows: rows, columns: columns)
