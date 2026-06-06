puts STDIN.read.gsub('\\n', "\n").gsub('\\t', "\t").gsub('\\r', "\r").gsub('\\"', '"').gsub('\\\\', '\\')
