# frozen_string_literal: true

require "digest"
require "set"

module Antares
  # The RegexLexer engine replaces these on every scan; retaining them would
  # also retain a whole source String and an output callback in every checkpoint.
  class LexerStateSnapshot
    VOLATILE = %i[@current_stream @output_stream @states @null_steps].freeze
    attr_reader :fingerprint, :bytesize

    def initialize(lexer, max_bytes: 256 * 1024)
      @value = self.class.copy(lexer)
      normalized = Marshal.dump(self.class.normalize(@value))
      raise ResourceLimitError, "lexer checkpoint exceeds #{max_bytes} bytes" if normalized.bytesize > max_bytes
      @bytesize = normalized.bytesize
      @fingerprint = Digest::SHA256.digest(normalized).freeze
      freeze
    end

    def restore = self.class.copy(@value)

    def self.fingerprint(value)
      Digest::SHA256.digest(Marshal.dump(normalize(value)))
    end

    def self.variables(value)
      names = value.instance_variables.sort
      value.is_a?(Rouge::Lexer) ? names - VOLATILE : names
    end

    def self.immutable?(value)
      value.nil? || value == true || value == false || value.is_a?(Numeric) || value.is_a?(Symbol) ||
        value.is_a?(Module) || value.is_a?(Regexp) || value.is_a?(Encoding) || value.is_a?(Rouge::RegexLexer::State)
    end

    def self.copy(value, memo = {})
      return value if immutable?(value)
      return memo[value.object_id] if memo.key?(value.object_id)
      raise UnsupportedLexerError, "lexer state graph exceeds 10000 objects" if memo.length >= 10_000
      case value
      when String
        memo[value.object_id] = value.dup
      when Array
        result = memo[value.object_id] = value.dup.clear
        value.each { |item| result << copy(item, memo) }
        variables(value).each { |name| result.instance_variable_set(name, copy(value.instance_variable_get(name), memo)) }
        result
      when Hash
        raise UnsupportedLexerError, "state Hash has a closure default" if value.default_proc
        result = memo[value.object_id] = value.dup.clear
        result.default = copy(value.default, memo)
        value.each { |key, item| result[copy(key, memo)] = copy(item, memo) }
        variables(value).each { |name| result.instance_variable_set(name, copy(value.instance_variable_get(name), memo)) }
        result
      when Set
        result = memo[value.object_id] = value.dup.clear
        value.each { |item| result.add(copy(item, memo)) }
        variables(value).each { |name| result.instance_variable_set(name, copy(value.instance_variable_get(name), memo)) }
        result
      when Struct
        result = memo[value.object_id] = value.dup
        value.each_pair { |name, item| result[name] = copy(item, memo) }
        result
      when Proc, Method, IO, StringScanner, MatchData
        raise UnsupportedLexerError, "cannot safely snapshot #{value.class}"
      else
        names = variables(value)
        raise UnsupportedLexerError, "opaque state object #{value.class}" if names.empty? && !value.is_a?(Rouge::Lexer)
        result = memo[value.object_id] = value.class.allocate
        names.each { |name| result.instance_variable_set(name, copy(value.instance_variable_get(name), memo)) }
        result
      end
    end

    def self.normalize(value, memo = {})
      case value
      when nil, true, false, Numeric, Symbol then value
      when String then [:string, value.encoding.name, value]
      when Regexp then [:regexp, value.source, value.options]
      when Module then [:module, value.name]
      when Encoding then [:encoding, value.name]
      when Rouge::RegexLexer::State
        # Static states are immutable rule templates. Dynamic states contain
        # closures, so identity is conservative: never converge distinct ones.
        [:state, value.name.is_a?(Symbol) ? value.name : value.object_id]
      else
        return [:reference, memo[value.object_id]] if memo.key?(value.object_id)
        raise UnsupportedLexerError, "lexer state graph exceeds 10000 objects" if memo.length >= 10_000
        memo[value.object_id] = memo.length
        case value
        when Array then [value.class.name, value.map { |item| normalize(item, memo) }, variables(value).map { |name| [name, normalize(value.instance_variable_get(name), memo)] }]
        when Hash
          raise UnsupportedLexerError, "state Hash has a closure default" if value.default_proc
          [value.class.name, normalize(value.default, memo), value.map { |key, item| [normalize(key, memo), normalize(item, memo)] }, variables(value).map { |name| [name, normalize(value.instance_variable_get(name), memo)] }]
        when Set then [value.class.name, value.map { |item| normalize(item, memo) }, variables(value).map { |name| [name, normalize(value.instance_variable_get(name), memo)] }]
        when Struct then [value.class.name, value.each_pair.map { |name, item| [name, normalize(item, memo)] }]
        else
          raise UnsupportedLexerError, "cannot fingerprint #{value.class}" if [Proc, Method, IO, StringScanner, MatchData].any? { |klass| value.is_a?(klass) }
          [value.class.name, variables(value).map { |name| [name, normalize(value.instance_variable_get(name), memo)] }]
        end
      end
    end
  end
end
