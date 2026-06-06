puts STDIN.read.sub(/\A([a-z])/) { |m| m.upcase }
