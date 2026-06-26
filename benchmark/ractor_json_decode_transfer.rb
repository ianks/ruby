# frozen_string_literal: true

begin
  require "etc"
  DEFAULT_POOL = [Etc.nprocessors, 12].min
rescue LoadError
  DEFAULT_POOL = 4
end

require "json"

PAYLOADS = Integer(ENV.fetch("RJB_PAYLOADS", "1000"))
POOL = Integer(ENV.fetch("RJB_POOL", DEFAULT_POOL.to_s))
CHUNK = Integer(ENV.fetch("RJB_CHUNK", "20"))
WARMUP = Integer(ENV.fetch("RJB_WARMUP", "1"))
REPEAT = Integer(ENV.fetch("RJB_REPEAT", "5"))
VARIANTS = Integer(ENV.fetch("RJB_VARIANTS", "8"))
METAFIELDS = Integer(ENV.fetch("RJB_METAFIELDS", "12"))
TAGS = Integer(ENV.fetch("RJB_TAGS", "12"))
MODES = ENV.fetch("RJB_MODES", "serial,decode_only,copy,move").split(",").map(&:strip)

def monotonic
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

def median(values)
  sorted = values.sort
  midpoint = sorted.length / 2

  if sorted.length.odd?
    sorted[midpoint]
  else
    (sorted[midpoint - 1] + sorted[midpoint]) / 2.0
  end
end

def product_payload(index)
  JSON.generate(
    "id" => index,
    "handle" => "product-#{index}",
    "title" => "Synthetic Product #{index}",
    "vendor" => "Ractor Bench",
    "available" => index.even?,
    "tags" => Array.new(TAGS) { |i| "tag-#{index % 17}-#{i}" },
    "price" => {
      "amount" => format("%d.%02d", 10 + (index % 90), index % 100),
      "currency" => "USD",
    },
    "variants" => Array.new(VARIANTS) do |variant|
      {
        "id" => (index * 100) + variant,
        "sku" => "SKU-#{index}-#{variant}",
        "title" => "Variant #{variant}",
        "available" => (index + variant).even?,
        "selected_options" => [
          { "name" => "Size", "value" => %w[XS S M L XL][variant % 5] },
          { "name" => "Color", "value" => %w[Black Blue Green Red][variant % 4] },
        ],
      }
    end,
    "metafields" => Array.new(METAFIELDS) do |field|
      {
        "namespace" => "bench",
        "key" => "field_#{field}",
        "value" => "value #{index}:#{field}",
        "type" => "single_line_text_field",
      }
    end,
    "images" => Array.new(4) do |image|
      {
        "id" => (index * 10) + image,
        "alt" => "Image #{image}",
        "src" => "https://example.test/products/#{index}/#{image}.jpg",
      }
    end,
  )
end

def build_payloads
  payloads = Array.new(PAYLOADS) { |index| product_payload(index) }
  Ractor.make_shareable(payloads)
end

def consume_objects(objects)
  objects.sum(&:length)
end

def attribution_phase(name)
  Ractor.__attribution_phase = name if Ractor.respond_to?(:__attribution_phase=)
  yield
ensure
  Ractor.__attribution_phase = :none if Ractor.respond_to?(:__attribution_phase=)
end

def run_serial(payloads)
  objects = Array.new(payloads.length) { |index| JSON.parse(payloads[index]) }
  consume_objects(objects)
end

def worker_loop(payloads, mode, result_port, worker_index)
  loop do
    job = Ractor.receive
    break :stopped if job == :stop

    job_id, start, count = job

    case mode
    when :decode_only
      checksum = 0
      attribution_phase(:json_parse) do
        count.times do |offset|
          checksum += JSON.parse(payloads[start + offset]).length
        end
      end
      attribution_phase(:decode_only_result_send) do
        result_port.send([worker_index, job_id, checksum], move: true)
      end
    when :copy
      objects = attribution_phase(:json_parse) do
        Array.new(count) { |offset| JSON.parse(payloads[start + offset]) }
      end
      attribution_phase(:copy_result_send) do
        result_port.send([worker_index, job_id, objects])
      end
    when :move
      objects = attribution_phase(:json_parse) do
        Array.new(count) { |offset| JSON.parse(payloads[start + offset]) }
      end
      attribution_phase(:move_result_send) do
        result_port.send([worker_index, job_id, objects], move: true)
      end
    else
      raise "unknown mode: #{mode.inspect}"
    end
  end
end

def dispatch(worker, state)
  return false if state[:next] >= PAYLOADS

  start = state[:next]
  count = [CHUNK, PAYLOADS - start].min
  job_id = state[:job_id]

  state[:next] += count
  state[:job_id] += 1
  attribution_phase(:dispatch_send) do
    worker.send([job_id, start, count], move: true)
  end
  true
end

def run_ractors(payloads, mode)
  result_port = Ractor::Port.new
  workers = Array.new(POOL) do |worker_index|
    Ractor.new(payloads, mode, result_port, worker_index) do |worker_payloads, worker_mode, port, index|
      worker_loop(worker_payloads, worker_mode, port, index)
    end
  end

  state = { next: 0, job_id: 0 }
  workers.each { |worker| dispatch(worker, state) }

  total_jobs = (PAYLOADS + CHUNK - 1) / CHUNK
  completed = 0
  checksum = 0

  while completed < total_jobs
    worker_index, _job_id, value = attribution_phase(:receive_consume) do
      result_port.receive
    end

    attribution_phase(:receive_consume) do
      checksum += mode == :decode_only ? value : consume_objects(value)
    end
    completed += 1
    dispatch(workers[worker_index], state)
  end

  attribution_phase(:worker_stop) do
    workers.each { |worker| worker.send(:stop) }
    workers.each(&:value)
  end

  checksum
end

def measure(label)
  WARMUP.times { yield }

  checksums = []
  times = Array.new(REPEAT) do
    start = monotonic
    checksums << yield
    monotonic - start
  end

  unless checksums.uniq.length == 1
    warn "#{label}: checksum varied: #{checksums.inspect}"
  end

  times
end

payloads = build_payloads
results = {}

puts RUBY_DESCRIPTION
puts "RACTOR_MOVE_PAGE_ADOPTION=#{ENV.fetch("RACTOR_MOVE_PAGE_ADOPTION", "0")}" \
     " RACTOR_MOVE_BULK_ALLOC=#{ENV.fetch("RACTOR_MOVE_BULK_ALLOC", "0")}" \
     " bulk_pages=#{ENV.fetch("RACTOR_MOVE_BULK_ALLOC_MAX_PAGES", "1024")}" \
     " payloads=#{PAYLOADS} pool=#{POOL} chunk=#{CHUNK}" \
     " variants=#{VARIANTS} metafields=#{METAFIELDS} tags=#{TAGS}" \
     " repeat=#{REPEAT} warmup=#{WARMUP} modes=#{MODES.join(",")}"
puts

runners = {
  "serial" => ["serial", -> { run_serial(payloads) }],
  "decode_only" => ["ractor decode-only", -> { run_ractors(payloads, :decode_only) }],
  "copy" => ["ractor copy", -> { run_ractors(payloads, :copy) }],
  "move" => ["ractor move", -> { run_ractors(payloads, :move) }],
}

MODES.each do |mode|
  label, runner = runners.fetch(mode) { raise "unknown RJB_MODES entry: #{mode.inspect}" }
  times = measure(label, &runner)
  results[label] = {
    min: times.min,
    median: median(times),
    max: times.max,
  }
end

baseline_label = results.key?("serial") ? "serial" : results.keys.first
baseline = results.fetch(baseline_label).fetch(:median)

puts "baseline=#{baseline_label}"
puts format("%-20s %10s %10s %10s %10s %10s", "mode", "min(s)", "median(s)", "max(s)", "payload/s", "vs base")
results.each do |label, data|
  payloads_per_second = PAYLOADS / data.fetch(:median)
  speedup = baseline / data.fetch(:median)

  puts format(
    "%-20s %10.4f %10.4f %10.4f %10.1f %10.2fx",
    label,
    data.fetch(:min),
    data.fetch(:median),
    data.fetch(:max),
    payloads_per_second,
    speedup,
  )
end
