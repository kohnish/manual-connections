#!/bin/bash
if rc-service transmission-daemon status |grep -q started; then
    rc-service transmission-daemon stop
fi
if pgrep qbittorrent-nox; then
    if [[ -f /opt/piavpn-manual/pia-port-forward-failure ]]; then
        rm -f -f /opt/piavpn-manual/pia-port-forward-failure
        date +%s > /opt/piavpn-manual/qbittorrent-start-flag
    else
        date +%s > /opt/piavpn-manual/qbittorrent-stop-time
    fi
    rc-service qbittorrent stop
fi
rc-service strongswan stop
iptables -P OUTPUT ACCEPT
iptables -F OUTPUT

nums=$(iptables -L INPUT -n --line-number | awk '/PIA_VPN/ {print $1}' | sort -r)
for idx in $nums; do
    iptables -D INPUT "$idx"
done

rc-service dnscrypt-proxy restart
if [[ -f /etc/resolv.conf.pia_bak ]]; then
    mv /etc/resolv.conf.pia_bak /etc/resolv.conf
fi
if [[ -f /etc/dhcpcd.conf.pia_bak ]]; then
    mv /etc/dhcpcd.conf.pia_bak /etc/dhcpcd.conf
    rc-service dhcpcd restart
fi
