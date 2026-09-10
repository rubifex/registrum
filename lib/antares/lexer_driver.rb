# frozen_string_literal: true

require "strscan"

module Antares
  # Reuses Rouge's own rule interpreter. Supplying the complete bounded source
  # preserves cross-line matches, fixed anchors and lookbehind at checkpoints.
  class LexerDriver
    attr_reader :lexer, :line, :scanner, :scanned_lines

    def self.supported?(lexer)
      lexer.is_a?(Rouge::RegexLexer) && lexer.method(:stream_tokens).owner == Rouge::RegexLexer
    end

    def initialize(lexer, source, offsets, start_line: 0, &emit)
      raise UnsupportedLexerError, "#{lexer.class.tag} has a custom stream driver" unless self.class.supported?(lexer)
      @lexer = lexer
      @source = source
      @offsets = offsets
      @line = start_line
      @scanned_lines = 0
      @emit = emit
      @tokens = []
      @scanner = StringScanner.new(source, fixed_anchor: true)
      @scanner.pos = offsets.fetch(start_line)
      lexer.instance_variable_set(:@current_stream, scanner)
      lexer.instance_variable_set(:@output_stream, method(:token).to_proc)
      lexer.instance_variable_set(:@states, lexer.class.states)
      lexer.instance_variable_set(:@null_steps, 0)
    end

    # Checkpoint only after an entire Rouge rule callback, never inside a yield:
    # callbacks frequently emit a token before updating their persistent state.
    def advance(until_line:)
      until scanner.eos? || line > until_line
        before = scanner.pos
        success = lexer.step(lexer.state, scanner)
        token(Rouge::Token::Tokens::Error, scanner.getch) unless success
        if scanner.pos > before && @tokens.empty? && scanner.pos == @offsets[line]
          return if block_given? && yield(line, lexer)
        end
      end
      if scanner.eos?
        finish_line unless @tokens.empty?
        finish_line while line < @offsets.length - 1
        yield(line, lexer) if block_given?
      end
      self
    end

    private

    def token(type, value)
      return if value.nil? || value.empty?
      value.each_line do |part|
        if @tokens.last&.first == type
          @tokens.last[1] << part
        else
          @tokens << [type, part.dup]
        end
        finish_line if part.end_with?("\n")
      end
    end

    def finish_line
      @emit.call(line, @tokens.map { |pair| pair[1].freeze; pair.freeze }.freeze)
      @tokens = []
      @line += 1
      @scanned_lines += 1
    end
  end
end
