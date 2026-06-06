puts STDIN.read.strip.gsub(/[\s\-._]+/, "_").gsub(/([A-Z])/) { |m| "_" + m.downcase }.gsub(/^_|_$/, "").split("_").map(&:capitalize).join
