require 'cgi'
puts CGI.escapeHTML(STDIN.read)
