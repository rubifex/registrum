# frozen_string_literal: true

require "benchmark"
require "objspace"
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "antares"

lexer = Rouge::Lexers::Python
lines = Array.new(5000) { |index| "value_#{index} = #{index}\n" }
highlighter = Antares::Highlighter.new(lexer: lexer.new, lines: ->(index) { lines[index] },
  line_count: -> { lines.length }, strategy: :incremental, max_seconds: 5)
first = Benchmark.realtime { highlighter.tokens_in(0...60) }
highlighter.advance(until_line: lines.length - 1)
samples = Array.new(30) do |iteration|
  Benchmark.realtime do
    lines[2496] = "value_2496 = #{iteration}\n"
    highlighter.edit(from_line: 2496, removed: 1, inserted: 1)
    highlighter.advance(until_line: 4999)
  end
end
median = samples.sort[samples.length / 2]
seen = {}
queue = highlighter.checkpoints.values.dup
retained_bytes = 0
until queue.empty?
  value = queue.pop
  next if Antares::LexerStateSnapshot.immutable?(value) || seen[value.object_id]
  seen[value.object_id] = true
  retained_bytes += ObjectSpace.memsize_of(value)
  case value
  when Array then queue.concat(value)
  when Hash then value.each { |key, item| queue << key << item }
  else value.instance_variables.each { |name| queue << value.instance_variable_get(name) }
  end
end
puts "#{lexer.tag}, 5000 lines: first 60=#{(first * 1000).round(3)} ms, edit+materialize+rescan median=#{(median * 1000).round(3)} ms"
puts "rescanned=#{highlighter.last_scanned_lines} lines, checkpoints=#{highlighter.checkpoints.length}, retained checkpoint bytes=#{retained_bytes}, normalized bytes=#{highlighter.checkpoint_bytes}"
if ENV["BUDGET"] == "1"
  raise "visible range exceeded 15 ms" unless first < 0.015
  raise "edit exceeded 5 ms" unless median < 0.005
  raise "checkpoints exceeded 2 MB" unless retained_bytes < 2_000_000
end
