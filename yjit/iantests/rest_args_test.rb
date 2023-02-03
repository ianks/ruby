# frozen_string_literal: true

require_relative 'test_helper'

class RestArgsTest < Test
  def test_without_rest_args
    stats = yjit_analyze(<<~RUBY)
      def this_shouldnt_exit(foo, args = []) = foo + 1
      def shouldnt_exit = this_shouldnt_exit(99)
      shouldnt_exit
    RUBY

    assert(stats.runtime(:compiled_block_count).positive?)
    assert_equal({}, stats.exits)
  end

  def test_empty_anonymous_rest_args
    stats = yjit_analyze(<<~RUBY)
      def this_shouldnt_exit(foo, *) = foo + 1
      def shouldnt_exit = this_shouldnt_exit(99)
      shouldnt_exit
    RUBY

    assert_equal({}, stats.exits)
  end

  def test_empty_named_rest_args
    stats = yjit_analyze(<<~RUBY)
      def this_shouldnt_exit(foo, *args) = foo + 1
      def shouldnt_exit = this_shouldnt_exit(99)
      shouldnt_exit
    RUBY

    assert_equal({}, stats.exits)
  end

end
