puts STDIN.read.gsub(/(.{1,80})(\s+|\Z)/, "\\1\n").rstrip
