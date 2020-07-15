require "http"

class Rory::Server
  getter host : String
  getter port : Int32
  getter storage_path : Path
  getter url_base : URI

  def initialize(@host, @port, storage_path, url_base)
    @storage_path = Path.new(storage_path.to_s)
    @url_base = URI.parse(url_base)
  end

  def start
    server = HTTP::Server.new(&->request(HTTP::Server::Context))

    puts "Listening on http://#{host}:#{port}"
    server.listen(host, port)
  end

  def request(context : HTTP::Server::Context)
    case context.request.path
    when "/upload"
      case context.request.method
      when "POST"
        upload_request(context)
      else
        context.response.respond_with_status(:method_not_allowed)
      end
    else
      context.response.respond_with_status(:not_found)
    end
  rescue ignored : Error
  end

  private def upload_request(ctx)
    # TODO: auth
    unless ctx.request.headers["Content-Type"]?.try &.starts_with?("multipart/form-data")
      error(ctx, :unsupported_media_type, "Uploads must be multipart/form-data")
    end

    HTTP::FormData.parse(ctx.request) do |part|
      case part.name
      when "file"
        id = Rory.proquint(Random::Secure.random_bytes(4))
        file_path = @storage_path/id

        File.open(file_path, "w") do |file|
          IO.copy(part.body, file)
          file.flush

          content_type = part.headers["Content-Type"]? || guess_mime_type(file_path)
          file.xattr["user.rory_mime_type"] = content_type
        end

        ctx.response.content_type = "text/plain"
        ctx.response.puts @url_base.resolve(id)
      end
    end
  end

  private def guess_mime_type(filename)
    process = Process.new("file", {"--mime-type", "--brief", filename.to_s}, output: :pipe, error: :inherit)
    output = process.output.gets_to_end
    status = process.wait
    raise "MIME type guessing failed" unless status.success?
    output.chomp
  end

  private def error(context, status : HTTP::Status, message : String)
    context.response.reset
    context.response.status = status
    context.response.content_type = "text/plain"
    context.response << message
    raise Error.new
  end

  class Error < Exception
  end
end
