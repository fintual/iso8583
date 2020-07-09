module ISO8583
  class Configuration
    attr_accessor :use_header, :header_position, :bitmap_position, :mti_position, :message_position

    def initialize
      @use_header = false
      @mti_position = 0
      @header_position = 1
      @bitmap_position = 2
      @message_position = 3
    end
  end
end
