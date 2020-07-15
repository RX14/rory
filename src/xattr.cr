lib LibC
  fun fgetxattr(fd : Int, name : Char*, value : Void*, size : SizeT) : SSizeT
  fun fsetxattr(fd : Int, name : Char*, value : Void*, size : SizeT, flags : Int) : Int
end

class File
  def xattr : Xattrs
    Xattrs::FD.new(self)
  end

  abstract struct Xattrs
    private abstract def setxattr(name : String, value : String)
    private abstract def getxattr(name : String) : String?

    def [](key : String) : String
      fetch(key)
    end

    def []?(key : String) : String?
      fetch(key, nil)
    end

    def []=(key : String, value : String) : String
      setxattr(key, value)
      value
    end

    def fetch(key : String)
      fetch(key) { raise KeyError.new("Missing xattr key: #{key.inspect}") }
    end

    def fetch(key : String, default)
      fetch(key) { default }
    end

    def fetch(key : String, &)
      if value = getxattr(key)
        value
      else
        yield key
      end
    end

    struct FD < Xattrs
      @fd : IO::FileDescriptor

      def initialize(@fd)
      end

      private def setxattr(name : String, value : String)
        if LibC.fsetxattr(@fd.fd, name, value, value.bytesize, 0) != 0
          raise IO::Error.from_errno "Unable to set extended attribute #{name}"
        end
      end

      private def getxattr(name : String) : String?
        size = LibC.fgetxattr(@fd.fd, name, nil, 0)
        if size < 0
          return nil if Errno.value == Errno::ENODATA
          raise IO::Error.from_errno "Unable to get extended attribute #{name}"
        end

        String.new(size) do |buf|
          new_size = LibC.fgetxattr(@fd.fd, name, buf, size)
          raise IO::Error.from_errno "Unable to get extended attribute #{name}" unless new_size >= 0
          raise "race condition" unless new_size == size
          {new_size, 0}
        end
      end
    end
  end
end
