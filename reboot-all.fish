#!/opt/homebrew/bin/fish

for ip in 235 236 237;
  talosctl -n "192.168.86.$ip" reboot
  sleep 120
end

