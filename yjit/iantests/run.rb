#!/usr/bin/env ruby

root = File.expand_path('..', __FILE__)
Dir[File.join(root, "**/*_test.rb")].each { |file| require file }
