require 'nokogiri'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class AwesomesauceGateway < Gateway
      include Empty

      self.test_url = 'http://sandbox.asgateway.com/'
      self.live_url = 'https://prod.awesomesauce.example.com/'

      # Only supports transactions in the US
      self.supported_countries = ['US']

      # Only supports transactions in US Dollars
      self.default_currency = 'USD'
      self.money_format = :dollars

      # The card types supported by the payment gateway
      self.supported_cardtypes = [:visa, :master, :american_express]

      # Homepage URL for the gateway
      self.homepage_url = 'http://sandbox.asgateway.com/'

      # Gateway Name
      self.display_name = 'Awesomesauce'

      # This Gateway uses custom error codes
      AWESOMESAUCE_ERROR_CODE = {
        '01' => 'Should never happen',
        '02' => 'Missing field',
        '03' => 'Bad format',
        '04' => 'Bad number',
        '05' => 'Arrest them!',
        '06' => 'Expired',
        '07' => 'Bad ref',
      }

      # An attempt to map the custom error codes to ActiveMerchant standard error codes
      STANDARD_ERROR_CODE_MAPPING = {
          '01' => STANDARD_ERROR_CODE[:card_declined],
          '02' => STANDARD_ERROR_CODE[:config_error],
          '03' => STANDARD_ERROR_CODE[:config_error],
          '04' => STANDARD_ERROR_CODE[:invalid_number],
          '05' => STANDARD_ERROR_CODE[:call_issuer],
          '06' => STANDARD_ERROR_CODE[:expired_card],
          '07' => STANDARD_ERROR_CODE[:card_declined],
      }

      def initialize(options={})
        requires!(options, :login, :password)
        super
      end

      def purchase(amount, payment, options={})
          commit(:purchase, build_auth_purchase('purch', amount, payment, options))
      end

      def authorize(amount, payment, options={})
        commit(:authorize, build_auth_purchase('auth', amount, payment, options))
      end

      def capture(authorization, options={})
        commit(:capture, build_capture_cancel('capture', authorization, options))
      end

      def refund( authorization, options={})
        commit(:refund, build_capture_cancel('cancel', authorization, options))
      end

      def void(authorization, options={})
        commit(:void, build_capture_cancel('cancel', authorization, options))
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
          gsub(%r((<secret>).+(</secret>)), '\1[FILTERED]\2').
          gsub(%r((<number>).+(</number>)), '\1[FILTERED]\2').
          gsub(%r((<cv2>).+(</cv2>)), '\1[FILTERED]\2')
      end

      private

      def build_auth_purchase(transaction_type, money, payment, options)
        @options[:url] = url + 'api/auth'

        builder = Nokogiri::XML::Builder.new do |xml|
          xml.request_ {
            xml.merchant_ @options[:login]
            xml.secret_ @options[:password]
            xml.action_ transaction_type
            xml.amount_ amount(money)
            xml.name_ payment.name
            xml.number_ payment.number
            xml.cv2 payment.verification_value
            xml.exp_ expiry_date(payment)
          }
        end
        if block_given?
          yield builder
        else
          formatted_no_decl = Nokogiri::XML::Node::SaveOptions::FORMAT +
                              Nokogiri::XML::Node::SaveOptions::NO_DECLARATION
          builder.to_xml( save_with:formatted_no_decl )
        end
      end

      def build_capture_cancel(transaction_type, ref, options)
        @options[:url] = url + 'api/ref'

        builder = Nokogiri::XML::Builder.new do |xml|
          xml.request do
            xml.merchant_ @options[:login]
            xml.secret_ @options[:password]
            xml.action_ transaction_type
            xml.ref_ ref
          end
        end
        if block_given?
          yield builder
        else
          formatted_no_decl = Nokogiri::XML::Node::SaveOptions::FORMAT +
                              Nokogiri::XML::Node::SaveOptions::NO_DECLARATION
          builder.to_xml( save_with:formatted_no_decl )
        end
      end

      def headers
        { 'Content-Type' => 'text/xml' }
      end

      def url
        test? ? test_url : live_url
      end

      # Format the expiration date in the way needed by the gateway
      def expiry_date(credit_card)
        "#{format(credit_card.month, :two_digits)}#{format(credit_card.year, :four_digits)}"
      end

      def parse(raw_response)
        xml = REXML::Document.new(strip_invalid_xml_chars(raw_response))

        response = {}
        # In the nominal case we don't care about the root node, so if it has child elements then don't bother with it
        if xml.root.has_elements?
          xml.root.elements.to_a.each do |node|
            parse_element(response, node)
          end
        else
          # However, if it is the only element it contains error data we are interested in, so we need to parse it
          parse_element(response, xml)
        end
        response
      end

      def parse_element(response, node)
        if node.has_elements?
          node.elements.each{|element| parse_element(response, element) }
        else
          response[node.name.underscore.to_sym] = node.text
        end
      end

      def strip_invalid_xml_chars(xml)
        xml.gsub(/&(?!(?:[a-z]+|#[0-9]+|x[a-zA-Z0-9]+);)/, '&amp;')
      end

      def commit(action, data)
          raw_response = ssl_post(@options[:url].to_s, data.to_s, headers)
          response = parse(raw_response)

          # We will get a hash key of :error when something has gone wrong with authentication check for that first
          if response[:error].nil?
          Response.new(success?(response), response[:err]? additional_message_from_response(response) : 'SUCCESS!!', response,
            {
                :authorization => response[:id],
                :test => test?,
                :error_code => error_code_from(response)
            }
          )
          else
            Response.new(false, 'ERROR: ' + response[:error],
              {
                  :error_code => STANDARD_ERROR_CODE[:processing_error]
              })
          end
      rescue StandardError # If you send invalid data the response causes an exception, catch and handle that.
          Response.new(false, action.to_s.upcase + ' failed with an Exception',
            {
                :error_code => STANDARD_ERROR_CODE[:processing_error]
            })

      end

      def success?(response)
        response[:success].to_s == 'true'
      end

      def additional_message_from_response(response)
          unless success?(response)
            AWESOMESAUCE_ERROR_CODE[response[:code].to_s]
          end
      end

      def error_code_from(response)
        unless success?(response)
          STANDARD_ERROR_CODE_MAPPING[response[:code].to_s]
        end
      end
    end
  end
end
