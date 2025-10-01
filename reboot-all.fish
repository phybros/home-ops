#!/opt/homebrew/bin/fish

set ips 235 236 237

for ip in $ips
  talosctl -n "192.168.86.$ip" reboot

  # Only sleep if not the last IP
  if test $ip != $ips[-1]
    sleep 120
  end
end
