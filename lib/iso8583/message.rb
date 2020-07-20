# Copyright 2009 by Tim Becker (tim.becker@kuriostaet.de)
# MIT License, for details, see the LICENSE file accompaning
# this distribution

module ISO8583

  # The class `Message` defines functionality to describe classes
  # representing different type of messages, or message families.
  # A message family consists of a number of possible message types that
  # are allowed, and a way of naming and encoding the bitmaps allowed in
  # the messages.
  #
  # To create your own message, start by subclassing Message:
  #
  #    class MyMessage < Message
  #       (...)
  #    end
  #
  # the subtyped message should be told how the MTI is encoded:
  #
  #    class MyMessage < Message
  #       mti_format N, :length => 4
  #       (...)
  #    end
  #
  # `N` above is an instance of Field which encodes numbers into their
  # ASCII representations in  a fixed length field. The option `length=>4`
  # indicates the length of the fixed field.
  #
  # Next, the allowed message types are specified:
  #
  #    class MyMessage < Message
  #       (...)
  #       mti 1100, "Authorization Request Acquirer Gateway"
  #       mti 1110, "Authorization Request Response Issuer Gateway"
  #       (...)
  #    end
  #
  # This basically defines to message types, 1100 and 1110 which may
  # be accessed later either via their name or value:
  #
  #    mes = MyMessage.new 1100
  # 
  # or
  #    mes = MyMessage.new "Authorization Request Acquirer Gateway"
  #
  # or
  #    mes = MyMessage.new
  #    mes.mti = 1110 # or Auth. Req. Acq. Gateway ...
  #
  # Finally the allowed bitmaps, their names and the encoding rules are
  # specified:
  #
  #    class MyMessage < Message
  #       (...)
  #       bmp  2, "Primary Account Number (PAN)",               LLVAR_N,   :max    => 19
  #       bmp  3,  "Processing Code",                           N,         :length =>  6
  #       bmp  4,  "Amount (Transaction)",                      N,         :length => 12
  #       bmp  6,  "Amount, Cardholder Billing" ,               N,         :length => 12
  #       (...)
  #    end
  #
  # The example above defines four bitmaps (2,3,4 and 6), and provides
  # their bitmap number and description. The PAN field is variable length
  # encoded (LL length indicator, ASCII, contents numeric, ASCII) and the
  # maximum length of the field is limited to 19 using options.
  #
  # The other fields are fixed length numeric ASCII fields (the length of the fields is
  # indicated by the `:length` options.)
  #
  # This message may be used as follows in order to interpret a received message.:
  #
  #    mes = MyMessage.parse inputData
  #    puts mes[2] # prints the PAN from the message.
  #
  # Constructing own messages works as follows:
  #
  #     mes = MyMessage.new 1100 
  #     mes[2]= 474747474747
  #
  # the convenience method bmp_alias may be used in defining the class in
  # order to provide direct access to fields using methods:
  #
  #    class MyMessage < Message
  #       (...)
  #       bmp  2, "Primary Account Number (PAN)",               LLVAR_N,   :max    => 19
  #       (...)
  #       bmp_alias 2, :pan
  #    end
  #
  # this allows accessing fields in the following manner:
  #
  #     mes = MyMessage.new 1100
  #     mes.pan = 474747474747
  #     puts mes.pan
  #     # Identical functionality to:
  #     mes[2]= 474747474747
  #
  # Most of the work in implementing a new set of message type lays in
  # figuring out the correct fields to use defining the Message class via
  # bmp.
  #    
  class Message

    # The value of the MTI (Message Type Indicator) of this message.
    attr_reader :mti 

    # Instantiate a new instance of this type of Message
    # optionally specifying an mti. 
    def initialize(mti = nil)
      # values is an internal field used to collect all the
      # bmp number | bmp name | field en/decoders | values
      # which are set in this message.
      @values = {}
      @headers = {}
      
      @hdr_defs = {}
      self.mti = mti if mti
    end

    # Set the mti of the Message using either the actual value
    # or the name of the message type that was defined using
    # Message.mti
    #
    # === Example
    #    class MyMessage < Message
    #      (...)
    #      mti 1100, "Authorization Request Acquirer Gateway"
    #    end
    #
    #    mes = MyMessage.new
    #    mes.mti = 1100 # or mes.mti = "Authorization Request Acquirer Gateway"
    def mti=(value)
      num, name = _get_mti_definition(value)
      @mti = num
    end
    
    # Set a field or header in this message, `key` is the bmp number or header key
    # ===Example
    #
    #    mes = BlaBlaMessage.new
    #    mes[2]=47474747                          # bmp 2 is generally the PAN
    #    mes['H1']=10                             # set header H1
    def []=(key, value)
      if _get_definition key
        if value.nil?
          @values.delete(key)
        else
          bmp_def = _get_definition key
          bmp_def.value = value
          @values[bmp_def.bmp] = bmp_def
        end
      elsif _get_hdr_definition(key)
        if value.nil?
          @headers.delete(key)
        else
          hdr_def = _get_hdr_definition key
          hdr_def.value = value
          @headers[hdr_def.bmp] = hdr_def
        end
      else
        raise ISO8583Exception.new "no definition for field: #{key}"
      end
    end

    # Retrieve the decoded value of the contents of a bitmap or header
    # described either by the bitmap number or header key.
    #
    # ===Example
    #
    #    mes = BlaBlaMessage.parse someMessageBytes
    #    mes[2] # bmp 2 is generally the PAN
    #    mes['H1'] # header H1
    def [](key)
      if _get_definition key
        bmp_def = _get_definition key
        bmp = @values[bmp_def.bmp]
        bmp ? bmp.value : nil
      elsif _get_hdr_definition(key)
        hdr_def = _get_hdr_definition key
        bmp = @headers[hdr_def.bmp]
        bmp ? bmp.value : nil
      else
        raise ISO8583Exception.new "no definition for field: #{key}"
      end
    end

    # Retrieve the byte representation of the bitmap.
    def to_b     
      sections = _body
      self.class.order
          .map { |k, _v| k }
          .reduce("".force_encoding('ASCII-8BIT')) do |cum, section|
        content = sections[section]
        cum += content.force_encoding('ASCII-8BIT')
      end
    end

    # Returns a nicely formatted representation of this
    # message.
    def to_s
      _mti_name = _get_mti_definition(mti)[1]
      str = "MTI: #{mti} (#{_mti_name})\n\n"
      _max = (@values.values + @headers.values).max do |a,b|
        a.name.length <=> b.name.length
      end
      _max_name = _max.name.length

      if ISO8583.configuration.use_header
        str += "HEADER\n"
        @headers.sort.each do |key, value|
          _bmp = @headers[key]
          str += ("%#{3}s %#{_max_name}s : %s\n" % [key, value.name, value.value])
        end
        str += "\n"
      end

      str += "MESSAGE\n"
      @values.sort.each do |key, value|
        str += ("%03d %#{_max_name}s : %s\n" % [key, value.name, value.value])
      end

      str
    end

    # Returns lengths of each part of the message.
    def lengths
      ret = Hash.bew
      _body.map do |key, val|
        ret[key] == val.length
      end

      ret[:all] = to_b.length
      ret
    end

    # METHODS starting with an underscore are meant for
    # internal use only ...
    
    # Returns an array of four byte arrays:
    # [header_bytes, mti_bytes, bitmap_bytes, message_bytes]
    def _body
      raise ISO8583Exception.new "no MTI set!" unless mti

      ret = Hash.new
      ret[:mti] = self.class._mti_format.encode(mti)
      ret[:header] = _header_body if ISO8583.configuration.use_header
      ret[:bitmap_and_message] = _bitmap_n_message_body

      ret
    end

    def _header_body
      header = "".force_encoding('ASCII-8BIT')
      @headers.sort.each do |key, value|
        header << value.encode
      end

      header
    end

    def _bitmap_n_message_body
      bitmap = Bitmap.new
      message = "".force_encoding('ASCII-8BIT')
      @values.sort.each do |key, value|
        bitmap.set(key)
        message << value.encode.force_encoding('ASCII-8BIT')
      end
      bitmap_s = ISO8583.configuration.use_hex_bitmap ? bitmap.to_hex : bitmap.to_bytes

      bitmap_s + message
    end

    def _get_definition(key) #:nodoc:
      b = self.class._definitions[key]
      return nil unless b

      b.dup
    end

    def _get_hdr_definition(key) #:nodoc:
      b = self.class._hdr_definitions[key]
      return nil unless b

      b.dup
    end

    # return [mti_num, mti_value] for key being either
    # mti_num or mti_value
    def _get_mti_definition(key)
      num_hash, name_hash = self.class._mti_definitions
      if num_hash[key]
        [key, num_hash[key]]
      elsif name_hash[key]
        [name_hash[key], key]
      else
        raise ISO8583Exception.new("MTI: #{key} not allowed!")
      end
    end

    class << self

      # Defines how the message type indicator is encoded into bytes. 
      # ===Params:
      # * field    : the decoder/encoder for the MTI
      # * opts     : the options to pass to this field
      #
      # === Example
      #     class MyMessage < Message
      #       mti_format N, :length =>4
      #       (...)
      #     end
      #
      # encodes the mti of this message using the `N` field (fixed
      # length, plain ASCII) and sets the fixed lengh to 4 bytes.
      #
      # See also: mti
      def mti_format(field, opts)
        f = field.dup
        _handle_opts(f, opts)
        @mti_format = f
      end
      
      # Defines the message types allowed for this type of message and
      # gives them names
      # 
      # === Example
      #    class MyMessage < Message
      #      (...)
      #      mti 1100, "Authorization Request Acquirer Gateway"
      #    end
      #
      #    mes = MyMessage.new
      #    mes.mti = 1100 # or mes.mti = "Authorization Request Acquirer Gateway"
      #
      # See Also: mti_format
      def mti(value, name)
        @mtis_v ||= {}
        @mtis_n ||= {}
        @mtis_v[value] = name
        @mtis_n[name] = value
      end

      # Define a bitmap in the message
      # ===Params:
      # * bmp   : bitmap number
      # * name  : human readable form
      # * field : field for encoding/decoding
      # * opts  : options to pass to the field, e.g. length for fxed len fields.
      #
      # ===Example
      #
      #    class MyMessage < Message
      #      bmp 2, "PAN", LLVAR_N, :max =>19
      #      (...)
      #    end
      #
      # creates a class MyMessage that allows for a bitmap 2 which 
      # is named "PAN" and encoded by an LLVAR_N Field. The maximum 
      # length of the value is 19. This class may be used as follows:
      #
      #    mes = MyMessage.new
      #    mes[2] = 474747474747 # or mes["PAN"] = 4747474747
      #
      def bmp(bmp, name, field, opts = nil)
        @defs ||= {}

        field = field.dup
        field.name = name
        field.bmp = bmp
        _handle_opts(field, opts) if opts
        
        bmp_def = BMP.new bmp, name, field

        @defs[bmp] = bmp_def
      end

      # Define a headers
      # ===Params:
      # * hdr   : bitmap number
      # * name  : human readable form
      # * field : field for encoding/decoding
      # * opts  : options to pass to the field, e.g. length for fxed len fields.
      #
      # ===Example
      #
      #    class MyMessage < Message
      #      hdr 'H1', "Header Length", B, :length => 1
      #      (...)
      #    end
      #
      # creates a class MyMessage that allows for a header 1 which
      # is named "Header Length" and encoded by an B Field. The
      # length of the value is 1. This class may be used as follows:
      #
      #    mes = MyMessage.new
      #    mes.hdr['H1'] = 4
      #
      def hdr(hdr, name, field, opts = nil)
        @hdr_defs ||= {}

        field = field.dup
        field.name = name
        field.bmp = hdr
        _handle_opts(field, opts) if opts

        hdr_def = BMP.new hdr, name, field

        @hdr_defs[hdr] = hdr_def
      end

      # Create an alias to access bitmaps directly using a method.
      # Example:
      #     class MyMessage < Message
      #         (...)
      #         bmp 2, "PAN", LLVAR_N
      #         (...)
      #         bmp_alias 2, :pan
      #     end #class
      #
      # would allow you to access the PAN like this:
      #
      #    mes.pan = 1234
      #    puts mes.pan
      #
      # instead of:
      #
      #    mes[2] = 1234
      #
      def bmp_alias(bmp, aliaz)
        define_method (aliaz) {
          bmp_ = @values[bmp]
          bmp_ ? bmp_.value : nil
        }

        define_method ("#{aliaz}=") {|value|
          self[bmp] = value
          # bmp_def = _get_definition(bmp)
          # bmp_def.value= value
          # @values[bmp] = bmp_def
        }
      end

      # Return render order as specified in configuration
      def order
        order = {
          mti: ISO8583.configuration.mti_position,
          bitmap_and_message: ISO8583.configuration.bitmap_and_message_position
        }
        order[:header] = ISO8583.configuration.header_position if ISO8583.configuration.use_header

        order.sort_by { |_k, v| v }
      end
      
      # Parse the bytes `str` returning a message of the defined type.
      def parse(str)
        str = str.force_encoding('ASCII-8BIT')
        message = self.new

        parsers = {
          mti: "_parse_mti",
          header: "_parse_header",
          bitmap_and_message: "_parse_bitmap_and_message"
        }

        order.map { |k, _v| k }
             .reduce("".force_encoding('ASCII-8BIT')) do |cum, section|
          puts "parsing #{section}"
          message, str = self.send(parsers[section], message, str)
        end

        message
      end

      def _parse_mti(message, str)
        message.mti, str = _mti_format.parse(str)
        
        [message, str]
      end

      def _parse_header(message, str)
        _hdr_definitions&.each do |key, bmp|
          header_len = bmp.field.length
          value = str.slice!(0...header_len)
          message[key] = value
        end

        [message, str]
      end

      def _parse_bitmap_and_message(message, str)
        bmp, str = Bitmap.parse(str)
        bmp.each do |bit|
          next if bit == 1

          bmp_def = _definitions[bit]
          value, str = bmp_def.field.parse(str)
          message[bit] = value
        end

        [message, str]
      end
      
      # access the mti definitions applicable to the Message
      #
      # returns a pair of hashes containing:
      #
      # mti_value => mti_name
      #
      # mti_name => mti_value
      #
      def _mti_definitions
        [@mtis_v, @mtis_n]
      end
      
      # Access the field definitions of this class, this is a
      # hash containing [bmp_number, BMP] and [bitmap_name, BMP]
      # pairs.
      #
      def _definitions
        @defs
      end

      def _hdr_definitions
        @hdr_defs
      end

      # Returns the field definition to format the mti.
      def _mti_format
        @mti_format
      end

      # Modifies the field definitions of the fields passed
      # in through the `bmp` and `mti_format` class methods.
      #
      def _handle_opts(field, opts)
        opts.each_pair {|key, value|
          key = (key.to_s+"=").to_sym
          if field.respond_to?(key)
            field.send(key, value)
          else
            warn "unknown option #{key} for #{field.name}"
          end
        }
      end
    end
  end

  # Internal class used to tie together name, bitmap number, field en/decoder
  # and the value of the corresponding field
  class BMP
    attr_accessor :bmp
    attr_accessor :name
    attr_accessor :field
    attr_accessor :value

    def initialize(bmp, name, field)
      @bmp = bmp
      @name = name
      @field = field
    end

    def encode
      field.encode(value)
    end
  end

end
