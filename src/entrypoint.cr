require "./rory"

host = ENV["HTTP_HOST"]? || "127.0.0.1"
port = ENV["HTTP_PORT"]?.try(&.to_i) || 8087
storage_path = ENV["RORY_STORAGE_PATH"]
url_base = ENV["RORY_URL_BASE"]? || "http://#{host}:#{port}"
tokens = ENV["RORY_TOKENS"].split(',')
Rory::Server.new(host, port, storage_path, url_base, tokens).start
