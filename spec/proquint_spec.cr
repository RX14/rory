require "./spec_helper"

describe Rory::Server do
  describe "#proquint" do
    it "works" do
      Rory.proquint(Bytes.new(0)).should eq("")
      Rory.proquint(Bytes[63, 118]).should eq("gutuk")

      Rory.proquint(Bytes[127, 0, 0, 1]).should eq("lusab-babad")
      Rory.proquint(Bytes[63, 84, 220, 193]).should eq("gutih-tugad")
      Rory.proquint(Bytes[63, 118, 7, 35]).should eq("gutuk-bisog")
      Rory.proquint(Bytes[140, 98, 193, 141]).should eq("mudof-sakat")
      Rory.proquint(Bytes[64, 255, 6, 200]).should eq("haguz-biram")
      Rory.proquint(Bytes[128, 30, 52, 45]).should eq("mabiv-gibot")
      Rory.proquint(Bytes[147, 67, 119, 2]).should eq("natag-lisaf")
      Rory.proquint(Bytes[212, 58, 253, 68]).should eq("tibup-zujah")
      Rory.proquint(Bytes[216, 35, 68, 215]).should eq("tobog-higil")
      Rory.proquint(Bytes[216, 68, 232, 21]).should eq("todah-vobij")
      Rory.proquint(Bytes[198, 81, 129, 136]).should eq("sinid-makam")
      Rory.proquint(Bytes[12, 110, 110, 204]).should eq("budov-kuras")
    end

    it "raises on odd byte length" do
      expect_raises(Exception, "data must be a multiple of 2 bytes") do
        Rory.proquint(Bytes[55])
      end
    end
  end
end
