# frozen_string_literal: true

require "timeout"
require "zlib"

module LexerCompatibility
  module_function

  def rows(lexer, source, line_count)
    result = Array.new(line_count) { [] }
    line = 0
    lexer.lex(source).each do |type, text|
      text.each_line do |part|
        row = result[line] ||= []
        row.last&.first == type.qualname ? row.last[1] << part : row << [type.qualname, part.dup]
        line += 1 if part.end_with?("\n")
      end
    end
    result
  end

  def samples(klass)
    demo = klass.demo.encode(Encoding::UTF_8).scrub
    demo = "plain text\nsecond line\n" if demo.empty?
    [demo, "\n#{demo}\n#{demo}\n", "#{demo}\n\t# Unicode λ 日本語\n/* open\nclose */\n\"quoted\" 'single'\n"]
  rescue Errno::ENOENT
    ["plain text\n", "first\nsecond\nthird\n", "# comment\n\"text\"\n"]
  end

  def mutate(lines, random, iteration)
    first = random.rand(lines.length + 1)
    available = lines.length - first
    removed = iteration % 3 == 0 ? 0 : [random.rand(1..3), available].min
    inserted = iteration % 3 == 1 ? [] : Array.new(random.rand(1..2)) do
      source = lines.empty? ? "value = 42\n" : lines.sample(random: random).dup
      characters = source.chomp.chars
      fragment = ["x", "\"", "'", "/*", "*/", "${", "\#{", "<", ">", ":", " ", "\t", "\\", "!", "λ"].sample(random: random)
      characters.insert(random.rand(characters.length + 1), fragment)
      characters.join + "\n"
    end
    lines[first, removed] = inserted
    [first, removed, inserted.length]
  end

  def check(klass, mutations: 50)
    checks = failures = 0
    first_failure = nil
    samples(klass).each_with_index do |source, sample|
      lines = source.lines
      random = Random.new(Zlib.crc32(klass.tag) + sample)
      highlighter = nil
      (0..mutations).each do |iteration|
        if iteration.positive?
          first, removed, inserted = mutate(lines, random, iteration)
          highlighter&.edit(from_line: first, removed: removed, inserted: inserted)
        end
        checks += 1
        begin
          expected = Timeout.timeout(2) { rows(klass.new, lines.join, lines.length) }
          highlighter ||= Antares::Highlighter.new(lexer: klass.new, lines: ->(index) { lines[index] },
            line_count: -> { lines.length }, strategy: :incremental, checkpoint_interval: 4, max_seconds: 2)
          actual = highlighter.tokens_in(0...lines.length).map { |row| row.map { |type, text| [type.qualname, text] } }
          unless actual == expected
            failures += 1
            mismatch = (0...[expected.length, actual.length].max).find { |index| actual[index] != expected[index] }
            first_failure ||= {reason: "token_mismatch", sample: sample, mutation: iteration, line: mismatch,
              expected: expected[mismatch].inspect[0, 240], actual: actual[mismatch].inspect[0, 240]}
          end
        rescue StandardError => error
          failures += 1
          first_failure ||= {reason: error.class.name, sample: sample, mutation: iteration, message: error.message[0, 240]}
          highlighter = nil
        end
      end
    end
    # Closing a distant, previously unterminated token can reclassify earlier
    # lines. This distinguishes line-state lexers from nonlocal regex grammars.
    [["/* open\n", "*/\n"], ["=begin\n", "=end\n"], ["value = \"\"\"\n", "\"\"\"\n"]].each_with_index do |(opening, closing), sample|
      lines = [opening] + Array.new(12, "continued text\n")
      checks += 1
      begin
        highlighter = Antares::Highlighter.new(lexer: klass.new, lines: ->(index) { lines[index] },
          line_count: -> { lines.length }, strategy: :incremental, checkpoint_interval: 4, max_seconds: 2)
        highlighter.tokens_in(0...lines.length)
        first = lines.length
        lines << closing
        highlighter.edit(from_line: first, removed: 0, inserted: 1)
        actual = highlighter.tokens_in(0...lines.length).map { |row| row.map { |type, text| [type.qualname, text] } }
        expected = Timeout.timeout(2) { rows(klass.new, lines.join, lines.length) }
        unless actual == expected
          failures += 1
          first_failure ||= {reason: "nonlocal_token", sample: sample, message: "closing a token changes lines before its edit checkpoint"}
        end
      rescue StandardError => error
        failures += 1
        first_failure ||= {reason: error.class.name, sample: sample, message: error.message[0, 240]}
      end
    end
    {strategy: failures.zero? ? :incremental : :window, checks: checks, failures: failures, failure: first_failure}
  end
end
