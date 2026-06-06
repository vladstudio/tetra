require 'uri'
puts URI.decode_www_form_component(STDIN.read.strip)
