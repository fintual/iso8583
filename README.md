# ISO 8583 Financial Messaging for Ruby

This package currently contains code for coding an decoding ISO 8583
Financial Message.

## Developing

In case you're using a ruby version >= 2.2, test-unit is no longer in
the std lib, so it needs to be available. Bundler installs this, if not
using bundler, you need to run `gem install test-unit` before running
the tests.

## Installing

You can install the last version of the +iso8583+ package by executing:

	gem install iso8583 

## Source

The source is most readily available on github[http://github.com/a2800276/8583].

## Mailing List

In case you discover bugs, spelling errors, offer suggestions for
improvements or would like to help out with the project, you can contact
me directly (tim@kuriositaet.de).

[![Build Status](https://travis-ci.org/a2800276/8583.svg?branch=master)](https://travis-ci.org/a2800276/8583)

## Adapted by Fintual

You may configure the gem using an initializer with the following abailable settings
```ruby
ISO8583.configure do |config|
  config.use_header = false # if you want to use include header in your message
  config.mti_position = 0
  config.header_position = 1
  config.bitmap_position = 2
	config.message_position = 3
end
```

Usage example
```ruby
module ISO8583
  class NetworkControlMessage < Message
    mti_format N, length: 4
    mti 800, "Mensaje de Control de Red"

    hdr 'H0', "Flag de Comienzo de Mensaje", AN, length: 3
    hdr 'H1', "Indicador de Producto", N, length: 2
    hdr 'H2', "Versión de Software", N, length: 2
    hdr 'H3', "Estado", N, length: 3
    hdr 'H4', "Origen del Requerimiento", N, length: 1
    hdr 'H5', "Origen de la Respuesta", N, length: 1

    bmp 7, "Fecha de transmisión del mensaje", YYMMDDhhmmss
    bmp 11, "Numero de trace", N, length: 12
    bmp 70, "Código identificador del mensaje", N, length: 3

    bmp_alias 7, :emission_date
    bmp_alias 11, :trace_number
    bmp_alias 70, :message_code

    def initialize(mti = nil)
      super(mti)

			# setup default header values
      @headers['H0'] = "ISO"
      @headers['H1'] = "03"
      @headers['H2'] = "20"
      @headers['H3'] = "000"
      @headers['H4'] = "0"
      @headers['H5'] = "0"
    end
  end
end

# Parse str message
ISO8583::NetworkControlMessage.parse(message)

# Create new message with mti 800
message = ISO8583::NetworkControlMessage.new 800
message.emission_date = "200708100000"
message.trace_number = 555
message.message_code = 1

# Output bytes
message.to_b

# Pretty print
message.to_s
```
