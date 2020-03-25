require 'rubygems'
require 'open-uri'
require 'nokogiri'
require 'money'

class InvalidCache < StandardError ; end

class EuCentralBank < Money::Bank::VariableExchange

  attr_accessor :last_updated
  attr_accessor :rates_updated_at

  ECB_RATES_URL = 'http://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml'
  CURRENCIES = %w(USD JPY BGN CZK DKK GBP HUF ILS LTL LVL PLN RON SEK CHF NOK HRK RUB TRY AUD BRL CAD CNY HKD IDR INR KRW MXN MYR NZD PHP SGD THB ZAR)
  EUR_CODE = 'EUR'.freeze

  def update_rates(cache=nil)
    update_parsed_rates(doc(cache))
  end

  def save_rates(cache)
    raise InvalidCache if !cache
    File.open(cache, "w") do |file|
      io = open(ECB_RATES_URL) ;
      io.each_line {|line| file.puts line}
    end
  end

  def update_rates_from_s(content)
    update_parsed_rates(doc_from_s(content))
  end

  def save_rates_to_s
    open(ECB_RATES_URL).read
  end

  def exchange(cents, from_currency, to_currency)
    exchange_with(Money.new(cents, from_currency), to_currency)
  end

  def calculate_rate(from_currency, to_currency)
    rate = get_rate(from_currency, to_currency)
    rate ||= (get_rate(EUR_CODE, to_currency) / get_rate(EUR_CODE, from_currency))
    rate.round(4)
  end

  def exchange_with(from, to_currency)
    rate = calculate_rate(from.currency.iso_code, to_currency)
    Money.new(((Money::Currency.wrap(to_currency).subunit_to_unit.to_f / from.currency.subunit_to_unit.to_f) * from.cents * rate).round, to_currency)
  end

  protected

  def doc(cache)
    rates_source = !!cache ? cache : ECB_RATES_URL
    Nokogiri::XML(open(rates_source)).tap {|doc| doc.xpath('gesmes:Envelope/xmlns:Cube/xmlns:Cube//xmlns:Cube') }
  rescue Nokogiri::XML::XPath::SyntaxError
    Nokogiri::XML(open(ECB_RATES_URL))
  end

  def doc_from_s(content)
    Nokogiri::XML(content)
  end

  def update_parsed_rates(doc)
    rates = doc.xpath('gesmes:Envelope/xmlns:Cube/xmlns:Cube//xmlns:Cube')

    rates.each do |exchange_rate|
      rate = exchange_rate.attribute("rate").value.to_f
      currency = exchange_rate.attribute("currency").value
      add_rate(EUR_CODE, currency, rate)
    end
    add_rate(EUR_CODE, EUR_CODE, 1)

    rates_updated_at = doc.xpath('gesmes:Envelope/xmlns:Cube/xmlns:Cube/@time').first.value
    @rates_updated_at = Time.parse(rates_updated_at)

    @last_updated = Time.now
  end
end
