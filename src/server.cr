require "http"

class Rory::Server
  getter host : String
  getter port : Int32
  getter storage_path : Path
  getter url_base : URI
  getter allowed_bearer_tokens = Array(String).new

  def initialize(@host, @port, storage_path, url_base, allowed_tokens)
    @storage_path = Path.new(storage_path.to_s)
    @url_base = URI.parse(url_base)

    allowed_tokens.each do |token|
      if bearer_token = token.lchop?("bearer:")
        allowed_bearer_tokens << bearer_token
      else
        raise "unknown token scheme #{token.split(':')[0].inspect} in #{token.inspect}"
      end
    end
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
        context.response.headers["Allow"] = "POST"
        return context.response.status = :method_not_allowed
      end
    else
      file_request(context)
    end
  rescue ignored : Error
  end

  private def file_request(ctx)
    file_path = @storage_path/ctx.request.path
    if File.exists?(file_path)
      unless ctx.request.method == "GET"
        ctx.response.headers["Allow"] = "GET"
        return ctx.response.status = :method_not_allowed
      end

      File.open(file_path) do |file|
        ctx.response.content_length = file.size
        ctx.response.content_type = file.xattr["user.rory_mime_type"]
        IO.copy(file, ctx.response)
      end
    else
      ctx.response.respond_with_status(:not_found)
    end
  end

  private def upload_request(ctx)
    authenticate_request(ctx)

    unless ctx.request.headers["Content-Type"]?.try &.starts_with?("multipart/form-data")
      error(ctx, :unsupported_media_type, "Uploads must be multipart/form-data")
    end

    ctx.response.content_type = "text/plain"

    HTTP::FormData.parse(ctx.request) do |part|
      case part.name
      when "file"
        if part.headers["X-Rory-Use-Filename"]?.try(&.downcase).in?("yes", "true")
          file_name = part.filename || error(ctx, :bad_request, "No filename supplied with X-Rory-Use-Filename")
        else
          file_name = Rory.proquint(Random::Secure.random_bytes(4))
        end
        file_path = @storage_path/file_name

        error(ctx, :bad_request, "File name #{file_name.inspect} already exists") if File.exists?(file_path)

        File.open(file_path, "w") do |file|
          IO.copy(part.body, file)
          file.flush

          if part.headers["X-Rory-Use-Content-Type"]?.try(&.downcase).in?("yes", "true")
            content_type = part.headers["Content-Type"]? || guess_mime_type(file_path)
          else
            content_type = guess_mime_type(file_path)
          end
          file.xattr["user.rory_mime_type"] = content_type
        end

        ctx.response.puts @url_base.resolve(file_name)
      else
        error(ctx, :bad_request, "Unknown form field #{part.name.inspect}")
      end
    end
  end

  private def authenticate_request(ctx)
    authorization = ctx.request.headers["Authorization"]?
    unless authorization
      error(ctx, :unauthorized, "Authorization required", {"WWW-Authenticate" => %(Bearer realm="example")})
    end

    credentials = authorization.split(" ")
    auth_scheme = credentials[0]
    token = credentials[1]?

    if auth_scheme != "Bearer"
      error(ctx, :unauthorized, "Authentication must use Bearer scheme",
        {"WWW-Authenticate" => %(Bearer realm="example")})
    end

    if !token || credentials.size > 2
      error(ctx, :bad_request, "Invalid syntax for Bearer authentication scheme")
    end

    unless @allowed_bearer_tokens.includes? token
      error(ctx, :unauthorized, "Invalid Bearer token",
        {"WWW-Authenticate" => %(Bearer realm="example", error="invalid_token")})
    end
  end

  private def guess_mime_type(filename)
    process = Process.new("file", {"--mime-type", "--brief", filename.to_s}, output: :pipe, error: :inherit)
    output = process.output.gets_to_end
    status = process.wait
    raise "MIME type guessing failed" unless status.success?
    output.chomp
  end

  private def error(context, status : HTTP::Status, message : String, headers = nil)
    context.response.reset
    context.response.headers.merge!(headers) if headers
    context.response.status = status
    context.response.content_type = "text/plain"
    context.response << message
    raise Error.new
  end

  class Error < Exception
  end
end
