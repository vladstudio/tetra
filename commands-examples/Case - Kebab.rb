puts STDIN.read.strip.gsub(/[\s\-._]+/, "-").gsub(/([A-Z])/) { |m| "-" + m.downcase }.gsub(/^-|-$/, "").downcase
