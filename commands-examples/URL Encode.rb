require 'uri'
puts URI.encode_www_form_component(STDIN.read.strip)
