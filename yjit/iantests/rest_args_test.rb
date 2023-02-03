# frozen_string_literal: true

require_relative 'test_helper'

require "bundler"

class RestArgsTest < Test
  def test_it_doesnt_have_exits_for_empty_rest_args
    # skip 'Not implemented yet'

    stats = yjit_analyze(<<~RUBY)
      def this_shouldnt_exit(foo, *args)
        foo + 1
      end

      def shouldnt_exit
        this_shouldnt_exit(99, 1, 2, 3)
      end

      shouldnt_exit
    RUBY

    pp stats.runtime_stats
    assert_equal({}, stats.exits)
  end

  def test_it_doesnt_have_exits_for_anonymous_rest_args
    skip 'Not implemented yet'

    stats = yjit_analyze(<<~RUBY)
      def this_shouldnt_exit(foo, *) = foo + 1
      def shouldnt_exit = this_shouldnt_exit(99, 1, 2, 3, 4, 5)
      shouldnt_exit
    RUBY

    assert_equal({}, stats.exits)
  end

  def test_no_exits_when_using_regular_args
    stats = yjit_analyze(<<~RUBY)
      def this_shouldnt_exit(foo, args=[])
        foo + 1
      end

      def shouldnt_exit
        this_shouldnt_exit(99, [1, 2, 3, 4, 5])
      end

      shouldnt_exit
    RUBY

    pp stats.runtime_stats
    assert_equal({}, stats.exits)
  end
end
