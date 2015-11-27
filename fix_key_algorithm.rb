require 'openssl'

unless ARGV.length == 1
  puts "Usage: #{__FILE__} keyfile.der"
  exit 1
end

pkey = OpenSSL::ASN1.decode(File.binread(ARGV[0]))
puts "Changing algorithm from #{pkey.value[1].value[0].value} to gost2001"
pkey.value[1].value[0].value = "gost2001"
File.binwrite(ARGV[0] + '.fixed.der', pkey.to_der)
puts "Saved to #{ARGV[0] + '.fixed.der'}"
