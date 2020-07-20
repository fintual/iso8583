module ISO8583
  class Configuration
    attr_accessor :use_header, :header_position, :mti_position, :bitmap_and_message_position, 
                  :use_hex_bitmap

    def initialize
      @use_header = false
      @mti_position = 0
      @header_position = 1
      @bitmap_and_message_position = 2
      @use_hex_bitmap = false
    end
  end
end
