#!/bin/bash

set -euo pipefail

log() {
    logger -t pia "$@"
}

log "Setting up kill switch"

vpn_src_ip=$(swanctl --list-sas --raw --ike pia-default | sed -n 's/.*local-vips=\[\([0-9\.]*\)\].*/\1/p')
iptables -A OUTPUT -s "${vpn_src_ip}" -m comment --comment "PIA_VPN_SRC_IP" -j ACCEPT

rc-service dnscrypt-proxy restart
if ! grep -q 'nameserver 127.0.0.1' /etc/resolv.conf; then
    if ! grep -q '^nohook resolv.conf' /etc/dhcpcd.conf; then
        log "Rewriting dhcpcd.conf to ignore dns server"
        cp /etc/dhcpcd.conf /etc/dhcpcd.conf.pia_bak
        printf '\nnohook resolv.conf\n' >> /etc/dhcpcd.conf
        rc-service dhcpcd restart
    fi
    log "Overriding resolv.conf"
    cp /etc/resolv.conf /etc/resolv.conf.pia_bak
    echo 'nameserver 127.0.0.1' > /etc/resolv.conf
fi

vpn_src_ip_only="${vpn_src_ip%/32}"

if [[ -f /var/lib/transmission/config/settings.json ]]; then
    transmission_ip=$(cat /var/lib/transmission/config/settings.json | jq '.["bind-address-ipv4"]')
    if [[ "$transmission_ip" != "$vpn_src_ip_only" ]]; then
        log "VPN ip address is different from the one configured in transmission"
        jq ".[\"bind-address-ipv4\"] = \"$vpn_src_ip_only\"" /var/lib/transmission/config/settings.json > /tmp/settings.json
        mv /tmp/settings.json /var/lib/transmission/config/settings.json
    fi
fi

if [[ -f /var/lib/qbittorrent/.config/qBittorrent/qBittorrent.conf ]]; then
    qbittorrent_ip_line=$(grep 'Session\\InterfaceAddress=' /var/lib/qbittorrent/.config/qBittorrent/qBittorrent.conf)
    qbittorrent_ip=$(echo "$qbittorrent_ip_line" | awk -F= '{print $2}')
    if [[ "$qbittorrent_ip" != "$vpn_src_ip_only" ]]; then
        stopped=0
        if pgrep qbittorrent-nox; then
            rc-service qbittorrent stop
            stopped=1
        fi
        sed -i 's/\(Session\\InterfaceAddress=\).*/\1'"$vpn_src_ip_only"'/' /var/lib/qbittorrent/.config/qBittorrent/qBittorrent.conf
        if [[ $stopped -eq 1 ]]; then
            rc-service qbittorrent start || true
            log "Starting qbittorrent for ip change"
        fi
    fi
fi

if [[ -f /opt/piavpn-manual/qbittorrent-start-flag ]]; then
    log "Port forward failure detected, starting qbittorrent"
    rm -f /opt/piavpn-manual/qbittorrent-start-flag
    rc-service qbittorrent start || true
elif [[ -f /opt/piavpn-manual/qbittorrent-stop-time ]]; then
    prev_time=$(cat /opt/piavpn-manual/qbittorrent-stop-time)
    rm /opt/piavpn-manual/qbittorrent-stop-time
    curr_time=$(date +%s)
    one_min_ago=$(($curr_time - 300))
    if [[ $prev_time -gt $one_min_ago ]]; then
        log "Restarting qbittorrent"
        rc-service qbittorrent start || true
    fi
fi

if swanctl --list-conns | grep -q -w pia-jp; then
    max_wait_attempt=30
    current_attempt=0
    while ! swanctl --list-sas --ike pia-jp | grep -q "pia-jp:.*ESTABLISHED"; do
        if [[ $current_attempt -gt $max_wait_attempt ]]; then
            log "pia-jp SA didn't come up"
            exit 1
        fi
        log "Waiting for PIA-JP SA to be up"
        sleep 0.5
        current_attempt=$(($current_attempt + 1))
    done

    jp_vpn_src_ip=$(swanctl --list-sas --raw | grep pia-jp | sed -n 's/.*local-vips=\[\([0-9\.]*\)\].*/\1/p')
    if [[ -n $jp_vpn_src_ip ]]; then
        iptables -A OUTPUT -s "${jp_vpn_src_ip}" -m comment --comment "PIA_VPN_SRC_IP_JP" -j ACCEPT
    fi
fi
