# frozen_string_literal: true

require "test_helper"
require_relative "support/lexer_compatibility"

class LexerCompatibilityTest < Minitest::Test
  def test_every_lexer_has_a_reproducible_compatibility_verdict
    lexers = Rouge::Lexer.all.sort_by(&:tag)
    assert_equal lexers.map(&:tag), Antares::COMPATIBILITY.keys.sort
    lexers.each do |lexer|
      result = LexerCompatibility.check(lexer)
      assert_equal Antares::COMPATIBILITY.fetch(lexer.tag), result[:strategy],
        "#{lexer.tag} changed: #{result.inspect}; regenerate script/compatibility --write for Rouge #{Rouge.version}"
      assert_equal 156, result[:checks]
      assert_equal 0, result[:failures], lexer.tag if result[:strategy] == :incremental
    end
  end
end
