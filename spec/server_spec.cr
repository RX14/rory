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

private def check_file(url : String, content : String, mime_type : String)
  path = URI.parse(url).path
  File.open(file_path(path)) do |file|
    file.gets_to_end.should eq(content)
    file.xattr["user.rory_mime_type"].should eq(mime_type)
  ensure
    file.delete
  end
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

      check_file(response.body, "hello world", "text/plain")
    end

    it "uploads multiple files" do
      response = formdata_request("POST", "/upload") do |builder|
        builder.file("file", IO::Memory.new("file1"))
        builder.file("file", IO::Memory.new("file2"))
      end
      response.status.should eq(HTTP::Status::OK)

      response.content_type.should eq("text/plain")
      response.body.lines.size.should eq(2)
      response.body.lines.each &.should start_with("https://example.com/")

      check_file(response.body.lines[0], "file1", "text/plain")
      check_file(response.body.lines[1], "file2", "text/plain")
    end

    it "guesses mime type" do
      response = formdata_request("POST", "/upload") do |builder|
        builder.file("file", IO::Memory.new(""))
      end
      response.status.should eq(HTTP::Status::OK)

      response.content_type.should eq("text/plain")
      response.body.should start_with("https://example.com/")
      response.body.lines.size.should eq(1)

      check_file(response.body, "", "inode/x-empty")
    end

    it "supports user-provided mime type" do
      response = formdata_request("POST", "/upload") do |builder|
        builder.file("file", IO::Memory.new(%q({"foo": "bar"})),
          headers: HTTP::Headers{"Content-Type"            => "text/plain",
                                 "X-Rory-Use-Content-Type" => "Yes"})
        builder.file("file", IO::Memory.new(%q({"foo": "bar"})),
          headers: HTTP::Headers{"Content-Type" => "text/plain"})
      end
      response.status.should eq(HTTP::Status::OK)

      response.content_type.should eq("text/plain")
      response.body.lines.size.should eq(2)
      response.body.lines.each &.should start_with("https://example.com/")

      check_file(response.body.lines[0], %q({"foo": "bar"}), "text/plain")
      check_file(response.body.lines[1], %q({"foo": "bar"}), "application/json")
    end

    describe "user-provided filename" do
      it "uploads" do
        response = formdata_request("POST", "/upload") do |builder|
          builder.file("file", IO::Memory.new("foo"),
            metadata: HTTP::FormData::FileMetadata.new("test.cr"),
            headers: HTTP::Headers{"X-Rory-Use-Filename" => "yes"})
          builder.file("file", IO::Memory.new("foo"))
        end
        response.status.should eq(HTTP::Status::OK)

        response.content_type.should eq("text/plain")
        response.body.lines.size.should eq(2)
        response.body.lines.each &.should start_with("https://example.com/")

        response.body.lines[0].should eq("https://example.com/test.cr")
        check_file(response.body.lines[0], "foo", "text/plain")
        check_file(response.body.lines[1], "foo", "text/plain")
      end

      it "errors on no filename supplied" do
        response = formdata_request("POST", "/upload") do |builder|
          builder.file("file", IO::Memory.new("foo"),
            headers: HTTP::Headers{"X-Rory-Use-Filename" => "yes"})
        end
        response.status.should eq(HTTP::Status::BAD_REQUEST)

        response.content_type.should eq("text/plain")
        response.body.should eq("No filename supplied with X-Rory-Use-Filename")
      end

      it "errors on filename conflict" do
        response = formdata_request("POST", "/upload") do |builder|
          builder.file("file", IO::Memory.new("foo"),
            metadata: HTTP::FormData::FileMetadata.new("test.cr"),
            headers: HTTP::Headers{"X-Rory-Use-Filename" => "yes"})
        end
        response.status.should eq(HTTP::Status::OK)

        response.content_type.should eq("text/plain")
        response.body.should eq("https://example.com/test.cr\n")

        response = formdata_request("POST", "/upload") do |builder|
          builder.file("file", IO::Memory.new("bar"),
            metadata: HTTP::FormData::FileMetadata.new("test.cr"),
            headers: HTTP::Headers{"X-Rory-Use-Filename" => "yes"})
        end
        response.status.should eq(HTTP::Status::BAD_REQUEST)

        response.content_type.should eq("text/plain")
        response.body.should eq("File name \"test.cr\" already exists")

        check_file("https://example.com/test.cr", "foo", "text/plain")
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

    it "errors on unknown field name" do
      response = formdata_request("POST", "/upload") do |builder|
        builder.file("file[]", IO::Memory.new("foo"))
        builder.file("file", IO::Memory.new(%q({"foo": "bar"})))
      end
      response.status.should eq(HTTP::Status::BAD_REQUEST)

      response.content_type.should eq("text/plain")
      response.body.should eq("Unknown form field \"file[]\"")
    end
  end
end
