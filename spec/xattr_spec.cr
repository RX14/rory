require "./spec_helper"

describe File do
  it "stores xattrs" do
    File.tempfile(dir: __DIR__) do |file|
      file.xattr["user.crystal_test"] = "foo bar baz"
      file.xattr["user.crystal_test"].should eq("foo bar baz")
      file.delete
    end
  end

  it "handles nonexistant xattr" do
    File.tempfile(dir: __DIR__) do |file|
      file.xattr["user.crystal_test"] = "foo bar baz"
      file.xattr["user.crystal_test"]?.should eq("foo bar baz")
      file.xattr["user.crystal_noop"]?.should be_nil
      file.delete
    end
  end
end
