require 'nokogiri'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class AwesomesauceGateway < Gateway
      include Empty

      self.test_url = 'http://sandbox.asgateway.com/'
      self.live_url = 'https://prod.awesomesauce.example.com/'

      self.supported_countries = ['US']
      self.default_currency = 'USD'
      self.money_format = :dollars
      self.supported_cardtypes = [:visa, :master, :american_express, :discover, :diners_club, :jcb, :maestro]

      self.homepage_url = 'http://sandbox.asgateway.com/'
      self.display_name = 'Awesomesauce'

      STANDARD_ERROR_CODE_MAPPING = {
          '01' => STANDARD_ERROR_CODE[:should_never_happen],
          '02' => STANDARD_ERROR_CODE[:missing_field],
          '03' => STANDARD_ERROR_CODE[:bad_format],
          '04' => STANDARD_ERROR_CODE[:bad_number],
          '05' => STANDARD_ERROR_CODE[:arrest_them!],
          '06' => STANDARD_ERROR_CODE[:expired],
          '07' => STANDARD_ERROR_CODE[:bad_ref],
      }

      def initialize(options={})
        requires!(options, [:merchant_id, :secret_key])
        super
      end

      def purchase(amount, payment, options={})
        commit(:purchase) do |xml|
          add_auth_purchase(xml, 'purch', amount, payment, options)
        end
      end

      def authorize(amount, payment, options={})
        commit(:authorize) do |xml|
          add_auth_purchase(xml, 'auth', amount, payment, options)
        end
      end

      def capture(authorization, options={})
        commit(:capture) do |xml|
          add_captureCancel(xml, 'capture', authorization, options)
        end
      end

      def refund( authorization, options={})
        commit(:refund) do |xml|
          add_captureCancel(xml, 'cancel', authorization, options)
        end
      end

      def void(authorization, options={})
        commit(:void) do |xml|
          add_captureCancel(xml, 'cancel', authorization, options)
        end
      end

      def verify(credit_card, options={})
        MultiResponse.run(:use_first_response) do |r|
          r.process { authorize(100, credit_card, options) }
          r.process(:ignore_result) { void(r.authorization, options) }
        end
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(%r((<merchant>).+(</merchant>)), '\1[FILTERED]\2').
          gsub(%r((<secret>).+(</secret>)), '\1[FILTERED]\2').
          gsub(%r((<number>).+(</number>)), '\1[FILTERED]\2').
          gsub(%r((<cv2>).+(</cv2>)), '\1[FILTERED]\2')
      end

      private

      def add_auth_purchase(xml, transaction_type, amount, payment, options)
        unless valid_payment(payment).nil?
          raise ArgumentError.new payment[:validate]
        end
        xml.request do
          add_login(xml,options)
          xml.action(transaction_type)
          xml.amount(amount)
          xml.name(payment[:name])
          xml.number(payment[:number])
          xml.cv2(payment[:verification_value])
          xml.exp(payment[:expiry_date])
        end
      end

      def add_captureCancel(xml, transaction_type, ref, options)
        xml.request do
          add_login(xml, options)
          xml.action(transaction_type)
          xml.ref(ref)
        end
      end

      def add_login(xml, options)
        xml.merchant(options[:merchant_id])
        xml.secret(options[:secret_key])
      end

      def headers
        { 'Content-Type' => 'text/xml' }
      end

      def url
        test? ? test_url : live_url
      end

      # @return [errors]
      def valid_payment(payment)
        unless payment.is_a?CreditCard
          raise ArgumentError.new 'Payment type must be a credit card'
        end
        payment[:validate]
      end

      def parse(action, raw_response)
        doc = Nokogiri::XML(raw_response)
        doc.remove_namespaces!

        response = {action: action}

        response[:response_code] = !!element.content if (element = doc.at_xpath('//response/success'))
        response[:response_reason_code] = element.content if (element = doc.at_xpath('//response/code'))
        response[:response_reason_text] = element.content.to_i if(element = doc.at_xpath('//response/err'))
        response[:authorization_code] = element.content if(element = doc.at_xpath('//response/id'))

        response
      end

      def commit(action, options = {}, &payload)
        raw_response = ssl_post(url, post_data(action, &payload), headers)
        response = parse(action, raw_response)


        Response.new(
          success_from(response),
          message_from(response),
          response,
          authorization: authorization_from(response),
          avs_result: AVSResult.new(code: response['some_avs_response_key']),
          cvv_result: CVVResult.new(response['some_cvv_response_key']),
          test: test?,
          error_code: error_code_from(response)
        )
      end

      def success_from(response); end

      def message_from(response); end

      def authorization_from(response); end

      def post_data(action, parameters = {}); end

      def error_code_from(response)
        unless success_from(response)
          # TODO: lookup error code for this response
        end
      end
    end
  end
end
