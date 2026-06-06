puts STDIN.read.lines.map { |l| l.sub(%r{^[ \t]*((?://+|#)[ \t]*)}, "") }.join
