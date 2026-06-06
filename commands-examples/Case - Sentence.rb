text = STDIN.read
result = text.gsub(/([.!?]\s+)([a-z])/) { $1 + $2.upcase }
result = result.sub(/\A\s*[a-z]/) { |m| m.upcase }
puts result
