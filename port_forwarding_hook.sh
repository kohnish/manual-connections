#!/bin/bash

set -euo pipefail

port=$1

log() {
    logger -t pia "$@"
}

iptables -A INPUT -p tcp --dport $port -m comment --comment "PIA_VPN_PORT" -j ACCEPT

if [[ -f /var/lib/transmission/config/settings.json ]]; then
    transmission_port=$(cat /var/lib/transmission/config/settings.json | jq '.["peer-port"]')
    if [[ "$transmission_port" != "$port" ]]; then
        log "Forwarded port is different from the one configured in transmission"
        jq ".[\"peer-port\"] = $port" /var/lib/transmission/config/settings.json > /tmp/settings.json
        mv /tmp/settings.json /var/lib/transmission/config/settings.json
        if rc-service transmission-daemon status |grep -q started; then
            log "reloading transmission for port change to $port"
            rc-service transmission-daemon reload
        else
            log "transmission is not running, skip reloading"
        fi
    else
        if rc-service transmission-daemon status |grep -q started; then
            log "Forcing udp to rebind for transmission"
            jq ".[\"peer-port\"] = 11111" /var/lib/transmission/config/settings.json > /tmp/settings.json
            mv /tmp/settings.json /var/lib/transmission/config/settings.json
            rc-service transmission-daemon reload
            sleep 0.5
            jq ".[\"peer-port\"] = $transmission_port" /var/lib/transmission/config/settings.json > /tmp/settings.json
            mv /tmp/settings.json /var/lib/transmission/config/settings.json
            rc-service transmission-daemon reload
        fi
    fi
fi

if [[ -f /var/lib/qbittorrent/.config/qBittorrent/qBittorrent.conf ]]; then
    qbittorrent_port_line=$(grep 'Session\\Port=' /var/lib/qbittorrent/.config/qBittorrent/qBittorrent.conf)
    qbittorrent_port=$(echo "$qbittorrent_port_line" | awk -F= '{print $2}')
    if [[ "$qbittorrent_port" != "$port" ]]; then
        stopped=0
        if pgrep qbittorrent-nox; then
            rc-service qbittorrent stop
            stopped=1
        fi
        sed -i 's/\(Session\\Port=\).*/\1'"$port"'/' /var/lib/qbittorrent/.config/qBittorrent/qBittorrent.conf
        if [[ $stopped -eq 1 ]]; then
            rc-service qbittorrent start || true
            log "Starting qbittorrent for port change"
        fi
    fi
fi
