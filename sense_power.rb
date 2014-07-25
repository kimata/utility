#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

# Script for power meter using the following parts
# - Power Meter module (IC: INA226)
#   https://strawberry-linux.com/catalog/items?code=12031
# - I2C LCD (IC: ST7032i)
#   https://strawberry-linux.com/catalog/items?code=27001

class CharacterLCD
  def initialize
    # initialize
    exec_cmd("i2cset -y 1 0x3e 0 0x39 0x14 0x78 0x5E 0x6c i")
    # display ON
    exec_cmd("i2cset -y 1 0x3e 0 0x0C 0x06 i")
    # contrast set
    exec_cmd("i2cset -y 1 0x3e 0 0x39 i")
    exec_cmd("i2cset -y 1 0x3e 0 0x72 i")
    # set instruction table 0
    exec_cmd("i2cset -y 1 0x3e 0 0x38 i")
    clear
  end

  def clear
    # clear display
    exec_cmd("i2cset -y 1 0x3e 0 0x01 i")
    set_cursor(0)
  end

  def display(text)
    exec_cmd("i2cset -y 1 0x3e 0x40 #{text.unpack('C*').join(' ')} i")
  end

  def set_cursor(pos)
    # set cursor position
    exec_cmd("i2cset -y 1 0x3e 0 0x#{(0x80 | pos).to_s(16)}")
  end

  def exec_cmd(cmd)
    val=`#{cmd} 2> /dev/null`
    raise StandardError, "FAIL: #{cmd}" unless $?.success?
    return val
  end
end

class PowerSenseor
  def initialize(dev_addr=0x40)
    @dev_addr = dev_addr
    @v_val = 0
    @c_val = 0
    @p_val = 0

    # shunt resistor = 0.002Ω
    exec_cmd("i2cset -y 1 0x#{dev_addr.to_s(16)} 0x05 0x0a 0x00 i")
    # conversion time = 332us, number of average = 16
    exec_cmd("i2cset -y 1 0x#{dev_addr.to_s(16)} 0x00 0x04 0x97 i")
  end

  def sense
    @v_val=exec_cmd("i2cget -y 1 0x#{@dev_addr.to_s(16)} 0x02 w")
    @c_val=exec_cmd("i2cget -y 1 0x#{@dev_addr.to_s(16)} 0x04 w")
    @p_val=exec_cmd("i2cget -y 1 0x#{@dev_addr.to_s(16)} 0x03 w")
  end

  def get_voltage
    return calc_voltage(@v_val)
  end

  def get_current
    return calc_current(@c_val)
  end

  def get_power
    return calc_power(@p_val)
  end

  def exec_cmd(cmd)
    val=`#{cmd} 2> /dev/null`
    raise StandardError, "FAIL: #{cmd}" unless $?.success?
    return val
  end

  def calc_voltage(v_val)
    v = [v_val.gsub(/0x(\w{4})\n/, '\1')].pack('H*').unpack('s')[0].abs
    v = v * 1.25 / 1000.0
    return v
  end

  def calc_current(c_val)
    c = [c_val.gsub(/0x(\w{4})\n/, '\1')].pack('H*').unpack('s')[0].abs
    c = c / 1000.0
    return c
  end

  def calc_power(p_val)
    p = [p_val.gsub(/0x(\w{4})\n/, '\1')].pack('H*').unpack('s')[0]
    p = p * 0.025
    return p
  end
end

def get_ip_addr
  ip_addr=`LC_ALL=C ifconfig eth0 | grep 'inet addr:'`.chomp
  if ip_addr.match(%r|inet addr:(\d+\.\d+\.\d+\.\d+)|)
    return $1
  else
    return 'UNKNOWN'
  end
end


require 'optparse'
params = ARGV.getopts('l')

data_list = []

Signal.trap(:INT){
  if params['l'] then
    printf("time\tvoltage\tcurrent\tpower\n")
    data_list.each{|data|
      printf("%10d\t%.3f\t%.3f\t%.3f\n", data[0], data[1], data[2], data[3])
    }
  end
  exit(0)
}

sensor = PowerSenseor.new
lcd = CharacterLCD.new

if !params['l']
  lcd.set_cursor(40)
  lcd.display(get_ip_addr)
  5.times{|i|
    lcd.set_cursor(0)
    lcd.display(sprintf('IP: %-5s', '#' * (5-i)));
    sleep(1)
  }
  lcd.clear
end

start_time = Time.now
i = 0
while true 
  sensor.sense
  v = sensor.get_voltage
  c = sensor.get_current
  p = sensor.get_power


  if params['l'] then
    data_list.push([(Time.now - start_time) * 1000, v, c, p])
  end

  if ((i & 0x1F) == 0) then
    lcd.set_cursor(0)
    lcd.display(sprintf("%.3fV, %.3fA", v, c))
    lcd.set_cursor(40)
    lcd.display(sprintf("%.3fW", p))
    lcd.display(((i & 0x20) == 0x20) ? [0x5F].pack('C') : ' ')
    lcd.set_cursor(0)
  end
  i = (i & 0xff) + 1
end
