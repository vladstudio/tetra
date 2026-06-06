lines = STDIN.read.lines
min_indent = lines.map { |l| l.match(/^(\s*)/)[1].size }.min || 0
puts lines.map { |l| l[min_indent..] || "\n" }.join
