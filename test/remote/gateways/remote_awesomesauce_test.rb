require 'test_helper'

class RemoteAwesomesauceTest < Test::Unit::TestCase
  def setup
    Base.mode = :test
    @gateway = AwesomesauceGateway.new(fixtures(:awesomesauce))

    @amount = 1000
    @error_one_cent= 1001
    @error_two_cent= 1002
    @credit_card = credit_card('4111111111111111')
    @declined_card = credit_card('9011000990139424')
    @options = {
      # Awesomesauce doesn't currently support additional data
    }
  end

  def test_successful_purchase
    # Given a valid transaction amount and payment method
    # When purchasing
    response = @gateway.purchase(@amount, @credit_card, @options)

    # Then SUCCESS!!
    assert_success response
    assert_equal 'SUCCESS!!', response.message
  end

  def test_failed_purchase
    # Given an invalid transaction amount
    # When purchasing
    response = @gateway.purchase(@error_one_cent, @credit_card, @options)

    # Then expect failure
    assert_failure response
    assert_equal 'Should never happen', response.message
  end

  def test_successful_authorize_and_capture
    # Given a valid purchase amount and payment method
    # When authorizing
    auth = @gateway.authorize(@amount, @credit_card, @options)
    # Then SUCCESS!!
    assert_success auth

    # Given a valid authorization reference id
    # When capturing
    assert capture = @gateway.capture(auth.authorization)
    # Then SUCCESS!!
    assert_success capture
    assert_equal 'SUCCESS!!', capture.message
  end

  def test_failed_authorize
    # Given an invalid purchase amount
    # When authoriing
    response = @gateway.authorize(@error_two_cent, @credit_card, @options)

    # Then expect failure
    assert_failure response
    assert_equal 'Missing field', response.message
  end

  # Awesomesauce doesn't currently support partial captures
  # Leaving the definition here as reference in case the interface changes in the future
  # def test_partial_capture ;

  def test_failed_capture
    # Given a successful authorization
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    # Given a successful capture
    assert capture = @gateway.capture(auth.authorization)
    assert_success capture

    # When voiding a non-authorization transaction
    response = @gateway.void(capture.authorization)

    # Then the transaction should fail
    assert_failure response
    assert_equal 'Should never happen', response.message
  end

  def test_invalid_capture
    # Given an invalid capture authorization ref id
    # When capturing
    response = @gateway.capture('')

    # Then expect failure and exception
    assert_failure response
    assert_equal 'CAPTURE failed with an Exception', response.message
  end

  def test_successful_refund
    # Given a successful purchase
    purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase

    # When refunding
    assert refund = @gateway.refund(purchase.authorization)

    # Then SUCCESS!!
    assert_success refund
    assert_equal 'SUCCESS!!', refund.message
  end

  # Awesomesauce doesn't currently support partial refunds
  # Leaving this definition here in case the interface ever changes
  # def test_partial_refund;

  def test_failed_refund
    # Given a successful purchase
    auth = @gateway.purchase(@amount, @credit_card, @options)
    assert_success auth

    # Given a successful refund
    assert refund = @gateway.refund(auth.authorization)
    assert_success refund

    # When refunding a non-purchase transaction
    response = @gateway.refund(refund.authorization)

    # Then the transaction should fail
    assert_failure response
    assert_equal 'Should never happen', response.message
  end

  def test_invalid_refund
    # Given an invalid authorization ref id
    # When refunding
    response = @gateway.refund('')

    # Then expect failure and exception
    assert_failure response
    assert_equal 'REFUND failed with an Exception', response.message
  end

  def test_successful_void
    # Given a successful authorization
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    # When voiding
    assert void = @gateway.void(auth.authorization)

    # Then SUCCESS!!
    assert_success void
    assert_equal 'SUCCESS!!', void.message
  end

  def test_failed_void
    # Given a successful authorization
    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    # Given a successful void
    assert void = @gateway.void(auth.authorization)
    assert_success void

    # When voiding a non-authorization transaction
    response = @gateway.void(void.authorization)

    # Then the transaction should fail
    assert_failure response
    assert_equal 'Should never happen', response.message
  end

  def test_invalid_void
    # Given an invalid authorization
    response = @gateway.void('')

    # Then expect failure and Exception
    assert_failure response
    assert_equal 'VOID failed with an Exception', response.message
  end

  def test_successful_verify
    response = @gateway.verify(@credit_card, @options)
    assert_success response
    assert_match %r{SUCCESS!!}, response.message
  end

  def test_failed_verify
    response = @gateway.verify(@declined_card, @options)
    assert_failure response
    assert_equal Gateway::STANDARD_ERROR_CODE[:invalid_number], response.error_code
  end

  def test_invalid_login
    gateway = AwesomesauceGateway.new(login: '', password: '')

    response = gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_match %r{ERROR: Invalid security}, response.message
  end

  def test_transcript_scrubbing
    transcript = capture_transcript(@gateway) do
      @gateway.purchase(@amount, @credit_card, @options)
    end
    transcript = @gateway.scrub(transcript)

    assert_scrubbed(@credit_card.number, transcript)
    assert_scrubbed(@credit_card.verification_value, transcript)
    assert_scrubbed(@gateway.options[:password], transcript)
  end

  end
