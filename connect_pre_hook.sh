#!/bin/bash

set -euo pipefail

IKEV2_SERVER_IP=$1

iptables -A OUTPUT -d "${IKEV2_SERVER_IP}/32" -m comment --comment "PIA_VPN_SERVER_IP" -j ACCEPT
