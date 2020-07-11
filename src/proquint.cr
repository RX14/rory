module Rory
  def self.proquint(data : Bytes)
    {% begin %}
      raise "data must be a multiple of 2 bytes" unless data.size.even?

      consonant = StaticArray[{{"bdfghjklmnprstvz".chars.map { |c| "#{c}.ord.to_u8".id }.splat}}]
      vowel = StaticArray[{{"aiou".chars.map { |c| "#{c}.ord.to_u8".id }.splat}}]

      String.build(data.size * 3) do |io|
        0.step(to: data.size - 2, by: 2) do |i|
          word = data.unsafe_fetch(i).to_i16 << 8 | data.unsafe_fetch(i + 1).to_i16

          io.write_byte consonant[word.bits(12...16)]
          io.write_byte vowel[word.bits(10...12)]
          io.write_byte consonant[word.bits(6...10)]
          io.write_byte vowel[word.bits(4...6)]
          io.write_byte consonant[word.bits(0...4)]
          io.write_byte '-'.ord.to_u8 unless i == data.size - 2
        end
      end
    {% end %}
  end
end
