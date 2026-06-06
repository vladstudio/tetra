puts STDIN.read.split(/\n{2,}/).map { |p| p.lines.map(&:strip).reject(&:empty?).join(" ") }.join("\n\n").rstrip
