#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'nokogiri'
require 'capybara'
require 'capybara/poltergeist'
require 'nokogiri'

DATA_FILE_PATH  = '/home/kimata/var/amaten.csv'
AMATEN_URL      = 'https://amaten.jp/exhibitions/index'
TARGET_PRICE    = 10000
INTERVAL        = 30 * 60 # 30minute

def fetch_price_list(url)
  Capybara.register_driver :poltergeist do |app|
    Capybara::Poltergeist::Driver.new(app, {:js_errors => false, :timeout => 1000 })
  end

  Capybara.default_selector = :xpath
  session = Capybara::Session.new(:poltergeist)
  session.driver.headers = {
    'User-Agent' => 'Mozilla/5.0 (Windows NT 6.1; WOW64; rv:9.0.1) Gecko/20100101 Firefox/9.0.1' 
  } 

  session.visit url
  
  doc = Nokogiri::HTML.parse(session.html)

  price_list = []
  doc.search("//table[@id='gift_list']//tr").each do |tr|
    price_list.push({
      value: tr.search("td[@class='cellValue']").text.gsub(/[\D]/,'').to_i,
      rate: tr.search("td[@class='cellRate']").text.gsub(/[^\d.]/,'').to_f,
    })
  end

  return price_list
end

File.open(DATA_FILE_PATH, 'a') {|f|
  loop do
    price_list = fetch_price_list(AMATEN_URL)
    price = price_list.find{|price| price[:value] == TARGET_PRICE }

    if price == nil
      sleep INTERVAL / 10
      next
    end

    f.printf("%s, %.1f\n", Time.now.strftime("%Y/%m/%d %H:%M"), price[:rate])

    sleep INTERVAL
  end
}
