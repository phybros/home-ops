#!/bin/sh

ips="235 236 237"

last_ip=$(echo $ips | awk '{print $NF}')

for ip in $ips; do
  talosctl -n "192.168.86.$ip" reboot

  # Only sleep if not the last IP
  if [ "$ip" != "$last_ip" ]; then
    sleep 120
  fi
done

