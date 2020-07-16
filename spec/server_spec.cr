require "./spec_helper"

private def request(method, resource, headers = nil, body = nil) : HTTP::Client::Response
  server = Rory::Server.new(
    host: "localhost",
    port: 0,
    storage_path: Path.new(ENV["RORY_STORAGE_PATH"]),
    url_base: "https://example.com/"
  )

  middleware = HTTP::Server.build_middleware([HTTP::ErrorHandler.new(verbose: true)], ->server.request(HTTP::Server::Context))
  processor = HTTP::Server::RequestProcessor.new(middleware)

  input = IO::Memory.new
  HTTP::Request.new(method, resource, headers, body).to_io(input)
  output = IO::Memory.new
  processor.process(input.rewind, output)

  HTTP::Client::Response.from_io(output.rewind)
end

private def formdata_request(method, resource, headers = HTTP::Headers.new)
  io = IO::Memory.new
  HTTP::FormData.build(io) do |builder|
    yield builder
    headers["Content-Type"] = builder.content_type
  end
  request(method, resource, headers, io.rewind)
end

private def file_path(*args)
  Path.new(ENV["RORY_STORAGE_PATH"]).join(*args)
end

describe Rory::Server do
  describe "POST /upload" do
    it "uploads files" do
      response = formdata_request("POST", "/upload") do |builder|
        builder.file("file", IO::Memory.new("hello world"))
      end
      response.status.should eq(HTTP::Status::OK)

      response.content_type.should eq("text/plain")
      response.body.should start_with("https://example.com/")
      response.body.lines.size.should eq(1)

      path = URI.parse(response.body).path
      File.open(file_path(path)) do |file|
        file.gets_to_end.should eq("hello world")
        file.xattr["user.rory_mime_type"].should eq("text/plain")
      end
    end

    it "uploads multiple files" do
      response = formdata_request("POST", "/upload") do |builder|
        builder.file("file", IO::Memory.new("file1"))
        builder.file("file", IO::Memory.new("file2"))
      end
      response.status.should eq(HTTP::Status::OK)

      response.content_type.should eq("text/plain")
      response.body.lines.size.should eq(2)
      response.body.lines[0].should start_with("https://example.com/")
      response.body.lines[1].should start_with("https://example.com/")

      path = URI.parse(response.body.lines[0]).path
      File.open(file_path(path)) do |file|
        file.gets_to_end.should eq("file1")
        file.xattr["user.rory_mime_type"].should eq("text/plain")
      end

      path = URI.parse(response.body.lines[1]).path
      File.open(file_path(path)) do |file|
        file.gets_to_end.should eq("file2")
        file.xattr["user.rory_mime_type"].should eq("text/plain")
      end
    end

    it "guesses mine type" do
      response = formdata_request("POST", "/upload") do |builder|
        builder.file("file", IO::Memory.new(""))
      end
      response.status.should eq(HTTP::Status::OK)

      response.content_type.should eq("text/plain")
      response.body.should start_with("https://example.com/")
      response.body.lines.size.should eq(1)

      path = URI.parse(response.body).path
      File.open(file_path(path)) do |file|
        file.gets_to_end.should eq("")
        file.xattr["user.rory_mime_type"].should eq("inode/x-empty")
      end
    end

    it "errors on missing Content-Type" do
      response = request("POST", "/upload")
      response.status.should eq(HTTP::Status::UNSUPPORTED_MEDIA_TYPE)

      response.content_type.should eq("text/plain")
      response.body.should eq("Uploads must be multipart/form-data")
    end

    it "errors on wrong Content-Type" do
      response = request("POST", "/upload", HTTP::Headers{"Content-Type" => "application/json"})
      response.status.should eq(HTTP::Status::UNSUPPORTED_MEDIA_TYPE)

      response.content_type.should eq("text/plain")
      response.body.should eq("Uploads must be multipart/form-data")
    end
  end
end
