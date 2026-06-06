puts STDIN.read.strip.gsub(/[\s\-._]+/, "_").gsub(/([A-Z])/) { |m| "_" + m.downcase }.gsub(/^_|_$/, "").split("_").map.with_index { |w, i| i == 0 ? w.downcase : w.capitalize }.join
