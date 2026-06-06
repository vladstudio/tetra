require 'cgi'
puts CGI.unescapeHTML(STDIN.read)
