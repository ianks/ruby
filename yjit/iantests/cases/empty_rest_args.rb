def this_shouldnt_exit(foo, *args)
  puts "foo: #{foo}"
  puts "args: #{args}"
  foo + 1
end
def shouldnt_exit
  this_shouldnt_exit(99, 1, 2, 3, 233234, "hello", "yjit is awesome")
end
shouldnt_exit
