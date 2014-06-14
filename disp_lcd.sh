#!/bin/bash

# Script fot I2C LCD (controllter: ST7032)
# https://strawberry-linux.com/catalog/items?code=27001

init() {
    # Initialize
    i2cset -y 1 0x3e 0x00 0x39 0x14 0x78 0x5E 0x6c i
    # Display ON
    i2cset -y 1 0x3e 0x00 0x0C 0x06 i
    sleep 0.25
    i2cset -y 1 0x3e 0x00 0x01 i
}

show_text() {
    text=`printf '%-16s' "$1" | perl -pe '$_ = join(" ", map { ord } split(//) )'`
    i2cset -y 1 0x3e 0x40 $text i
    sleep 0.1
    if [ -n "$2" ]; then    
	text=`printf '%-16s' "$2" | perl -pe '$_ = join(" ", map { ord } split(//) )'`
	i2cset -y 1 0x3e 0 0xA8
	i2cset -y 1 0x3e 0x40 $text i
    fi
    i2cset -y 1 0x3e 0x00 0x80
}

show_icon() {
    i2cset -y 1 0x3e 0x00 0x39 0x44 i
    i2cset -y 1 0x3e 0x40 0x10 i
    i2cset -y 1 0x3e 0x00 0x02 i
}

get_ip_addr() {
    echo `LC_ALL=C ifconfig eth0 | grep 'inet addr:' | sed -e 's/^.*inet addr://' -e 's/ .*//'`
}

init
show_icon

while true; do
    show_text "IP:"`get_ip_addr` "`date \"+'%y/%m/%d %H:%M\"`"
    sleep 30
done

