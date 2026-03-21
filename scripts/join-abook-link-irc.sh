#!/bin/bash
# Connect to ABooK Link IRC channel on SynIRC
# Uses TLS on port 6697 for encrypted connection
set -euo pipefail

NICK="${1:-theartificer}"
SERVER="irc.synirc.net"
PORT="6697"

exec irssi -c "${SERVER}" -p "${PORT}" -n "${NICK}"
