# frozen_string_literal: true

require "json"
require 'open3'

begin
  require 'maxitest/autorun'
rescue LoadError
  require 'minitest/autorun'
end

ROOT = File.expand_path('../..', __dir__)

# Just a wrapper around the runtime stats hash for convenience
class YStats
  attr_reader :runtime_stats

  def initialize(runtime_stats)
    @runtime_stats = runtime_stats
  end

  def exits
    Hash[runtime_stats.select { |k, v| k.to_s.start_with?('exit_') && v > 0 }]
  end

  def runtime(key)
    runtime_stats.fetch(key)
  end
end

module Helpers
  module_function
  def yjit_analyze(incode)
    code = <<~RUBY
      #{incode}
      stats = RubyVM::YJIT.runtime_stats
      require "json"
      puts "runtime-stats 👉" + stats.to_json
      exit(0)
    RUBY

    args = ['--yjit', '--yjit-stats', '--yjit-call-threshold=1', '-e', code]
    out, err, status = Open3.capture3("#{ROOT}/ruby", *args)
    abort(err) unless status.success?
    json = out.match(/^runtime-stats 👉(.*)$/)[1]
    stats = JSON.parse(json, symbolize_names: true)
    YStats.new(stats)
  end

  def make_yjit!
    Dir.chdir(ROOT) do
      warn '⌛️ Building YJIT...'
      _out, err, status = Open3.capture3('make', '-j4')
      abort err unless status.success?
    end
  end
end

class Test < Minitest::Test
  include Helpers
end

Helpers.make_yjit!
