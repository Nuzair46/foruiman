# frozen_string_literal: true

# All subprocess behavior is Ruby-only; no shell utilities or Rails required.
require "json"
require "io/wait"
$stdout.sync = $stderr.sync = true

mode = ARGV.shift
case mode
when "streams"
  $stdout.puts "stdout message"
  warn "stderr message"
when "env"
  puts JSON.generate(ENV.to_h.slice(*ARGV).merge("cwd" => Dir.pwd, "stdin_eof" => $stdin.read.empty?))
when "exit"
  puts "before exit"
  exit Integer(ARGV.fetch(0))
when "exit_when_ready"
  sleep 0.01 until File.exist?(ARGV.fetch(0))
  puts "exit after peer ready"
  exit Integer(ARGV.fetch(1))
when "partial"
  print "partial"
  sleep 0.15
  print " line\nlast"
when "burst"
  count = Integer(ARGV.fetch(0, "20000"))
  count.times { |index| puts "line #{index}" }
when "long"
  print "x" * ((16_384 * 20) + 1)
when "watch"
  puts "stdin tty=#{$stdin.tty?}"
  ready = $stdin.wait_readable(0.2)
  eof = ready && $stdin.read_nonblock(1, exception: false).nil?
  puts(eof ? "stdin closed" : "watching")
  loop { sleep 1 }
when "input"
  puts "stdin tty=#{$stdin.tty?}"
  print "debug> "
  line = $stdin.gets
  puts "received #{line&.chomp.inspect}"
  loop { sleep 1 }
when "ticker", "ignore_term"
  Signal.trap("TERM", "IGNORE") if mode == "ignore_term"
  File.write(ARGV[0], Process.pid.to_s) if ARGV[0]
  puts "ready #{Process.pid}"
  loop do
    puts "tick #{Process.pid}"
    sleep 0.03
  end
when "tree", "orphan"
  file = ARGV.fetch(0)
  child = fork do
    Signal.trap("TERM", "IGNORE")
    grandchild = fork do
      Signal.trap("TERM", "IGNORE")
      loop { sleep 1 }
    end
    File.write(file, [Process.ppid, Process.pid, grandchild].join("\n"))
    loop { sleep 1 }
  end
  sleep 0.01 until File.exist?(file)
  puts "tree ready #{child}"
  exit 0 if mode == "orphan"

  loop { sleep 1 }
when "crash_tui"
  require "foruiman"
  require "foruiman/tui/application"
  terminal = Foruiman::TUI::Terminal.new
  engine = Foruiman::Engine.new(term_timeout: 0.1)
  engine.register("tree", ARGV.fetch(0))
  renderer = Foruiman::TUI::Renderer.new
  renderer.define_singleton_method(:render) do |*args, **options|
    raise "injected renderer failure" if File.exist?(ARGV.fetch(1))

    super(*args, **options)
  end
  begin
    Foruiman::TUI::Application.new(engine, terminal: terminal, renderer: renderer).run
  rescue RuntimeError
    exit 17
  end
end
