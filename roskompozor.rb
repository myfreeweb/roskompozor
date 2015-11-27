# ROSKOMPOZOR - a script for Russian ISPs that fetches the censorship list
# (for everyone else, it's this one: https://github.com/zapret-info/z-i)

CERT_PATH             = ENV["CERT_PATH"]             || "company.cert.pem"
KEY_PATH              = ENV["KEY_PATH"]              || "company.key.der"
KEY_FORMAT            = ENV["KEY_FORMAT"]            || "DER"
DATES_PATH            = ENV["DATES_PATH"]            || "dates.yml"
OPENSSL_BIN_PATH      = ENV["OPENSSL_BIN_PATH"]      || "/opt/gost-ssl/bin/openssl"
WANTED_DUMP_FORMAT    = ENV["WANTED_DUMP_FORMAT"]    || "2.2"
DUMP_DESTINATION_PATH = ENV["DUMP_DESTINATION_PATH"] || "dump.zip"
WSDL_URL              = ENV["WSDL_URL"]              || "http://vigruzki.rkn.gov.ru/services/OperatorRequestTest/?wsdl"
#WSDL_URL             = "http://vigruzki.rkn.gov.ru/services/OperatorRequest/?wsdl"


require 'openssl'
require 'base64'
require 'yaml/store'
require 'gyoku'
require 'savon'
require 'httpi'
require 'excon'
HTTPI.adapter = :excon
Excon.defaults[:middlewares] << Excon::Middleware::RedirectFollower

puts "=> ROSKOMPOZOR is using OpenSSL from #{OPENSSL_BIN_PATH}, key in #{KEY_FORMAT} format from #{KEY_PATH}, cert from #{CERT_PATH}, talking to WSDL service at #{WSDL_URL}"

def get_last_dump_times(client)
  puts "\n==> Getting last dump times / service metadata..."
  service_meta = client.call(:get_last_dump_date_ex).body[:get_last_dump_date_ex_response]
  puts "===> RKN service version #{service_meta[:web_service_version]}, dump format version #{service_meta[:dump_format_version]}, docs version #{service_meta[:doc_version]}"
  last_dump = Time.at service_meta[:last_dump_date].to_i/1000
  last_dump_urgent = Time.at service_meta[:last_dump_date_urgently].to_i/1000
  puts "===> Last dump: #{last_dump}, last urgent dump: #{last_dump_urgent}"
  [last_dump, last_dump_urgent]
end

def create_signed_request
  puts "\n==> Creating a signed request..."
  crt = OpenSSL::X509::Certificate.new File.binread(CERT_PATH)
  certname = Hash[crt.subject.to_a.map { |x| [x[0], x[1]] }]
  puts "===> Parsed the certificate"

  reqtext = '<?xml version="1.0" encoding="windows-1251"?>' + Gyoku.xml(:request => {
    :request_time  => Time.now.strftime("%FT%T.000%:z"),
    :operator_name => certname["CN"].force_encoding("windows-1251"),
    :inn           => certname["1.2.643.3.131.1.1"],
    :ogrn          => certname["1.2.643.100.1"],
    :email         => certname["emailAddress"]
  })
  puts "===> Created the request: #{reqtext}"

  reqfile = Tempfile.new 'roskompozor', :encoding => 'windows-1251'
  reqfile << reqtext
  reqfile.close
  reqpath = reqfile.path
  puts "===> Wrote the request to a temp file: #{reqpath}"

  signpath = reqpath + ".sign"
  rescode = system OPENSSL_BIN_PATH, "smime", "-sign", "-binary", "-signer", CERT_PATH, \
    "-inkey", KEY_PATH, "-keyform", KEY_FORMAT, \
    "-outform", "PEM", "-in", reqpath, "-out", signpath
  unless rescode
    puts "===> Signing failed"
    exit 1
  end
  puts "===> Signed the temp file: #{signpath}"
  [reqpath, signpath]
end

def enqueue_request(client, reqpath, signpath)
  puts "\n==> Sending the request to the queue..."
  response = client.call(:send_request, message: {
    "requestFile"       => Base64.encode64(File.binread(reqpath)).chop,
    "signatureFile"     => Base64.encode64(File.binread(signpath)).chop,
    "dumpFormatVersion" => WANTED_DUMP_FORMAT
  }).body[:send_request_response]
  unless response[:result]
    puts "===> Failed to enqueue the request! Comment: #{response[:result_comment]}"
    exit 1
  end
  puts "===> Successfully enqueued the request! Code: #{response[:code]} Comment: #{response[:result_comment]}"
  response[:code]
end

def fetch_dump(client, code)
  puts "\n==> Fetching the dump..."
  loop do
    puts "===> Waiting a minute"
    sleep 60
    puts "===> Trying to download"
    response = client.call(:get_result, message: { "code" => code }).body[:get_result_response]
    puts "===> Response: #{response[:result_code]} #{response[:result_comment]}"
    if response[:result]
      File.binwrite(DUMP_DESTINATION_PATH, Base64.decode64(response[:register_zip_archive]))
      puts "===> Archive written to #{DUMP_DESTINATION_PATH}"
      puts "===> Downloaded for #{response[:operator_name]}, INN #{response[:inn]}"
      break
    elsif response[:result_code] != 0
      puts "===> Fetching the dump failed!"
      break
    end
  end
end

store = YAML::Store.new(DATES_PATH)
client = Savon.client(:wsdl => WSDL_URL)

last_dump, last_dump_urgent = get_last_dump_times(client)
store.transaction do
  prev_last_dump, prev_last_dump_urgent = store[:last_dump], store[:last_dump_urgent]
  unless prev_last_dump.nil? || prev_last_dump_urgent.nil?
    puts "===> Previous last dump: #{prev_last_dump}, previous last urgent dump: #{prev_last_dump_urgent}"
    unless last_dump_urgent > prev_last_dump_urgent || last_dump.day != prev_last_dump.day
      puts "===> No updates detected, exiting"
      exit 0
    end
  else
    puts "===> No dates of previous dump"
  end
end

reqpath, signpath = create_signed_request
code = enqueue_request(client, reqpath, signpath)
fetch_dump(client, code)

store.transaction do
  store[:last_dump], store[:last_dump_urgent] = last_dump, last_dump_urgent
end
