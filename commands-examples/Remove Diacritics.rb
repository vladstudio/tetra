puts STDIN.read.unicode_normalize(:nfd).gsub(/\p{Mn}/, "")
