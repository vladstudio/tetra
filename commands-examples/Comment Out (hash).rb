puts STDIN.read.lines.map { |l| l.strip.empty? ? l : "# #{l}" }.join
