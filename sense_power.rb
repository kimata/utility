#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

IOCTL_I2C_SLAVE = 0x0703

# Script for power meter using the following parts
# - Power Meter module (IC: INA226)
#   https://strawberry-linux.com/catalog/items?code=12031
# - I2C LCD (IC: ST7032i)
#   https://strawberry-linux.com/catalog/items?code=27001

class CharacterLCD
  def initialize(i2c_bus=1, dev_addr=0x3E)
    @i2c = File.open(sprintf('/dev/i2c-%d', i2c_bus), 'rb+')
    @i2c.ioctl(IOCTL_I2C_SLAVE, dev_addr)

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
    @i2c.write("\x40" + text)
    @i2c.flush
  end

  def set_cursor(pos)
    # set cursor position
    @i2c.write("\x00" + [(0x80 | pos)].pack('C'))
    @i2c.flush
  end

  def exec_cmd(cmd)
    val=`#{cmd} 2> /dev/null`
    raise StandardError, "FAIL: #{cmd}" unless $?.success?
    return val
  end
end

class PowerSenseor
  def initialize(i2c_bus=1, dev_addr=0x40)
    @i2c = File.open(sprintf('/dev/i2c-%d', i2c_bus), 'rb+')
    @i2c.ioctl(IOCTL_I2C_SLAVE, dev_addr)

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
    @i2c.write(0x02)
    @v_val = conver_signed(@i2c.read(2))

    @i2c.write(0x04)
    @c_val = conver_signed(@i2c.read(2))

    @i2c.write(0x03)
    @p_val = conver_signed(@i2c.read(2))
  end

  def conver_signed(bytes)
    # convert endian
    return bytes.unpack('n').pack('S').unpack('s')[0].abs
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
    return v_val * 1.25 / 1000.0
  end

  def calc_current(c_val)
    return c_val / 1000.0
  end

  def calc_power(p_val)
    return p_val * 0.025
  end
end

def get_ip_addr
  iface_list = %w(wlan0 eth0)
  iface_list.each{|iface|
    ip_addr=`LC_ALL=C ifconfig #{iface} | grep 'inet addr:'`.chomp
    if ip_addr.match(%r|inet addr:(\d+\.\d+\.\d+\.\d+)|)
      return $1
    end
  }
  return 'UNKNOWN'
end

require 'optparse'
params = ARGV.getopts('lq')

data_list = []

Signal.trap(:INT){
  if params['l'] then
    printf("time,voltage,current,power\n")
    data_list.each{|data|
      printf("%10d,%.3f,%.3f,%.3f\n", data[0], data[1], data[2], data[3])
    }
  end
  exit(0)
}

sensor = PowerSenseor.new
lcd = CharacterLCD.new

if !params['l'] && !params['q']
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

  if ((i & 0x7F) == 0) then
    lcd.set_cursor(0)
    lcd.display(sprintf("%6.3fV %6.3fA", v, c))
    lcd.set_cursor(40)
    lcd.display(sprintf("%6.3fW", p))
    lcd.display(((i & 0x80) == 0x80) ? [0x5F].pack('C') : ' ')
    lcd.set_cursor(0)
  else
    sleep 0.001    
  end
  i = (i & 0xff) + 1
end
