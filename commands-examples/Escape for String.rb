puts STDIN.read.gsub('\\', '\\\\\\\\').gsub('"', '\\"').gsub("\n", '\\n').gsub("\t", '\\t').gsub("\r", '\\r')
