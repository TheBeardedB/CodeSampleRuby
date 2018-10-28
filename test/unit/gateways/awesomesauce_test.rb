require 'test_helper'

class AwesomesauceTest < Test::Unit::TestCase
  include CommStub

  def setup

    Base.mode = :test

    @gateway = AwesomesauceGateway.new(:password => '80300a3a5fa60424daa983936ae94fa5b449dc8a1267ec',
                                       :login => 'SampleLogin-api')

    @credit_card = credit_card
    @amount = 100  # $1 and 0 cents

    @options = {
    }
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response

    assert_equal '57561', response.authorization
    assert response.test?
  end

  def test_failed_purchase
    @gateway.expects(:ssl_post).returns(failed_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal Gateway::STANDARD_ERROR_CODE[:card_declined], response.error_code
  end

  def test_successful_authorize
    @gateway.expects(:ssl_post).returns(successful_authorize_response)

    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response

    assert_equal '57563', response.authorization
    assert response.test?
  end

  def test_failed_authorize
    @gateway.expects(:ssl_post).returns(failed_authorize_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal Gateway::STANDARD_ERROR_CODE[:card_declined], response.error_code
  end

  def test_successful_capture
    authorization = '58123'
    @gateway.expects(:ssl_post).returns(successful_capture_response)

    response = @gateway.capture(authorization, @options)
    assert_success response
    assert_equal authorization, response.authorization
    assert response.test?
  end

  def test_failed_capture
    authorization = '58126'
    @gateway.expects(:ssl_post).returns(failed_capture_response)

    response = @gateway.capture(authorization, @options)
    assert_failure response
    assert_equal Gateway::STANDARD_ERROR_CODE[:card_declined], response.error_code
    assert_equal authorization, response.authorization
  end

  def test_successful_refund
    authorization = '58127'
    @gateway.expects(:ssl_post).returns(successful_refund_response)

    response = @gateway.refund(authorization, @options)
    assert_success response
    assert_equal authorization, response.authorization
    assert response.test?
  end

  def test_failed_refund
    authorization = '58128'
    @gateway.expects(:ssl_post).returns(failed_refund_response)

    response = @gateway.refund(authorization, @options)
    assert_failure response
    assert_equal Gateway::STANDARD_ERROR_CODE[:card_declined], response.error_code
    assert_equal authorization, response.authorization
  end

  def test_successful_void
    authorization = '58129'
    @gateway.expects(:ssl_post).returns(successful_void_response)

    response = @gateway.void(authorization, @options)
    assert_success response
    assert_equal authorization, response.authorization
    assert response.test?
  end

  def test_failed_void
    authorization = '58130'
    @gateway.expects(:ssl_post).returns(failed_void_response)

    response = @gateway.void(authorization, @options)
    assert_failure response
    assert_equal Gateway::STANDARD_ERROR_CODE[:card_declined], response.error_code
    assert_equal authorization, response.authorization
  end

  def test_successful_verify
    @gateway.expects(:ssl_post).times(2).returns(successful_authorize_response, successful_void_response)

    response = @gateway.verify(@credit_card, @options)
    assert_success response
  end

  def test_successful_verify_with_failed_void
    @gateway.expects(:ssl_post).times(2).returns(successful_authorize_response, failed_void_response)

    response = @gateway.verify(@credit_card, @options)
    assert_success response
  end

  def test_failed_verify
    @gateway.expects(:ssl_post).returns(failed_authorize_response)

    response = @gateway.verify(@credit_card, @options)
    assert_failure response
  end

  def test_scrub
    assert @gateway.supports_scrubbing?
    assert_equal @gateway.scrub(pre_scrubbed), post_scrubbed
  end

  def test_strip_invalid_xml_chars
    xml = <<EOF
      <response>
        <element>Parse the First & but not this &tilde; &x002a;</element>
      </response>
EOF
    parsed_xml = @gateway.send(:strip_invalid_xml_chars, xml)

    assert REXML::Document.new(parsed_xml)
    assert_raise(REXML::ParseException) do
      REXML::Document.new(xml)
    end
  end

  private

  def pre_scrubbed
    %q(
      opening connection to sandbox.asgateway.com:80...
      opened
      <- "POST /api/auth HTTP/1.1\r\nContent-Type: text/xml\r\nConnection: close\r\nAccept-Encoding: gzip;q=1.0,deflate;q=0.6,identity;q=0.3\r\nAccept: */*\r\nUser-Agent: Ruby\r\nHost: sandbox.asgateway.com\r\nContent-Length: 314\r\n\r\n"
      <- "<request>\n  <merchant>SampleLogin-api</merchant>\n  <secret>1734c886350e7bcba84b6bc57e591e035d55f0ba2d2a1b86804eddb386c81239a1290b569b7229b6</secret>\n  <action>purch</action>\n  <amount>10.00</amount>\n  <name>Longbob Longsen</name>\n  <number>4111111111111111</number>\n  <cv2>123</cv2>\n  <exp>092019</exp>\n</request>\n"
      -> "HTTP/1.1 200 OK \r\n"
      -> "Connection: close\r\n"
      -> "Content-Type: text/html;charset=utf-8\r\n"
      -> "Content-Length: 118\r\n"
      -> "X-Xss-Protection: 1; mode=block\r\n"
      -> "X-Content-Type-Options: nosniff\r\n"
      -> "X-Frame-Options: SAMEORIGIN\r\n"
      -> "Server: WEBrick/1.3.1 (Ruby/2.2.1/2015-02-26)\r\n"
      -> "Date: Fri, 02 Nov 2018 16:02:23 GMT\r\n"
      -> "Set-Cookie: rack.session=BAh7CEkiD3Nlc3Npb25faWQGOgZFVEkiRTc5ZDE0NzE3MmMwMTBlMjJhN2Vj%0AM2Q2ZGM5MmIwZjE2MDJkZDk3MjY5YWJmODBhNmRjZTQyNmQ2OGU5ZmJkM2EG%0AOwBGSSIJY3NyZgY7AEZJIiUyOTdlMTI5M2UzNzI2M2VkNmY3NDFjYzRhNzY0%0AOWZlYwY7AEZJIg10cmFja2luZwY7AEZ7B0kiFEhUVFBfVVNFUl9BR0VOVAY7%0AAFRJIi0xOGU0MGUxNDAxZWVmNjdlMWFlNjllZmFiMDlhZmI3MWY4N2ZmYjgx%0ABjsARkkiGUhUVFBfQUNDRVBUX0xBTkdVQUdFBjsAVEkiLWRhMzlhM2VlNWU2%0AYjRiMGQzMjU1YmZlZjk1NjAxODkwYWZkODA3MDkGOwBG%0A--c69e40b5cdfc84eb032b1e4e14bf5c50970e7300; path=/; HttpOnly\r\n"
      -> "Via: 1.1 vegur\r\n"
      -> "\r\n"
      reading 118 bytes...
      -> "<response><merchant>SampleLogin-api</merchant><success>true</success><code></code><err></err><id>57520</id></response>"
      read 118 bytes
      Conn close
    )
  end

  def post_scrubbed
    %q(
      opening connection to sandbox.asgateway.com:80...
      opened
      <- "POST /api/auth HTTP/1.1\r\nContent-Type: text/xml\r\nConnection: close\r\nAccept-Encoding: gzip;q=1.0,deflate;q=0.6,identity;q=0.3\r\nAccept: */*\r\nUser-Agent: Ruby\r\nHost: sandbox.asgateway.com\r\nContent-Length: 314\r\n\r\n"
      <- "<request>\n  <merchant>SampleLogin-api</merchant>\n  <secret>[FILTERED]</secret>\n  <action>purch</action>\n  <amount>10.00</amount>\n  <name>Longbob Longsen</name>\n  <number>[FILTERED]</number>\n  <cv2>[FILTERED]</cv2>\n  <exp>092019</exp>\n</request>\n"
      -> "HTTP/1.1 200 OK \r\n"
      -> "Connection: close\r\n"
      -> "Content-Type: text/html;charset=utf-8\r\n"
      -> "Content-Length: 118\r\n"
      -> "X-Xss-Protection: 1; mode=block\r\n"
      -> "X-Content-Type-Options: nosniff\r\n"
      -> "X-Frame-Options: SAMEORIGIN\r\n"
      -> "Server: WEBrick/1.3.1 (Ruby/2.2.1/2015-02-26)\r\n"
      -> "Date: Fri, 02 Nov 2018 16:02:23 GMT\r\n"
      -> "Set-Cookie: rack.session=BAh7CEkiD3Nlc3Npb25faWQGOgZFVEkiRTc5ZDE0NzE3MmMwMTBlMjJhN2Vj%0AM2Q2ZGM5MmIwZjE2MDJkZDk3MjY5YWJmODBhNmRjZTQyNmQ2OGU5ZmJkM2EG%0AOwBGSSIJY3NyZgY7AEZJIiUyOTdlMTI5M2UzNzI2M2VkNmY3NDFjYzRhNzY0%0AOWZlYwY7AEZJIg10cmFja2luZwY7AEZ7B0kiFEhUVFBfVVNFUl9BR0VOVAY7%0AAFRJIi0xOGU0MGUxNDAxZWVmNjdlMWFlNjllZmFiMDlhZmI3MWY4N2ZmYjgx%0ABjsARkkiGUhUVFBfQUNDRVBUX0xBTkdVQUdFBjsAVEkiLWRhMzlhM2VlNWU2%0AYjRiMGQzMjU1YmZlZjk1NjAxODkwYWZkODA3MDkGOwBG%0A--c69e40b5cdfc84eb032b1e4e14bf5c50970e7300; path=/; HttpOnly\r\n"
      -> "Via: 1.1 vegur\r\n"
      -> "\r\n"
      reading 118 bytes...
      -> "<response><merchant>SampleLogin-api</merchant><success>true</success><code></code><err></err><id>57520</id></response>"
      read 118 bytes
      Conn close
    )
  end

  def successful_purchase_response
    %(
      <response><merchant>SampleLogin-api</merchant><success>true</success><code></code><err></err><id>57561</id></response>
    )
  end

  def failed_purchase_response
    %(
      <response><merchant>SampleLogin-api</merchant><success>false</success><code>01</code><err>Sandbox error</err><id>57562</id></response>
    )
  end

  def successful_authorize_response
    %(
      <response><merchant>SampleLogin-api</merchant><success>true</success><code></code><err></err><id>57563</id></response>
    )
  end

  def failed_authorize_response
    %(
      <response><merchant>SampleLogin-api</merchant><success>false</success><code>01</code><err>Sandbox error</err><id>57564</id></response>
    )
  end

  def successful_capture_response
    %(
    <response><merchant>SampleLogin-api</merchant><success>true</success><code></code><err></err><id>58123</id></response>
    )
  end

  def failed_capture_response
    %(
      <response><merchant>SampleLogin-api</merchant><success>false</success><code>01</code><err>action</err><id>58126</id></response>
    )
  end

  def successful_refund_response
    %(
      <response><merchant>SampleLogin-api</merchant><success>true</success><code></code><err></err><id>58127</id></response>
    )
  end

  def failed_refund_response
    %(
      <response><merchant>SampleLogin-api</merchant><success>false</success><code>01</code><err>action</err><id>58128</id></response>
    )
  end

  def successful_void_response
    %(
      <response><merchant>SampleLogin-api</merchant><success>true</success><code></code><err></err><id>58129</id></response>
    )
  end

  def failed_void_response
    %(
      <response><merchant>SampleLogin-api</merchant><success>false</success><code>01</code><err>action</err><id>58130</id></response>
    )
  end
end
