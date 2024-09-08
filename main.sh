#!/bin/sh
#
# Usage:
# ROUTER=192.168.1.254 ACCESS_CODE='sdf#$%SD' ./main.sh
#
# Developers: please make sure this shell script is compatible with `bash`,
# `dash` and `busybox`. A user may run it on a compact machine or a router that
# doesn't have a rich and fully functioning bash.

if [ -z "$ROUTER" ]; then
  echo "Environment variable ROUTER is required to be set to your router's admin interface's host name (usually an IP address)." >&2
  exit 1
fi

if [ -z "$ACCESS_CODE" ]; then
  echo "Environment variable ACCESS_CODE is required to be set to the access code to login to your router." >&2
  exit 1
fi

set -o errexit
set -o pipefail

restart_url="http://$ROUTER/cgi-bin/restart.ha"
login_url="http://$ROUTER/cgi-bin/login.ha"

cookies="/tmp/att-router-reboot-cookies.txt"
form1="/tmp/att-router-reboot-form1.txt"
form2="/tmp/att-router-reboot-form2.txt"
done="/tmp/att-router-reboot-done.txt"
rm -f "$cookies" "$form1" "$form2" "$done"

find_nonce() {
  grep 'name="nonce"' "$@" | egrep -o '[0-9a-f]{15,}'
}

get_md5() {
  python -c "import hashlib; print(hashlib.md5(r'$1'.encode('utf-8')).hexdigest())"
}

# Request 1: Fetch the restart page (may end up with a login form or a message prompting for cookies)
curl -b "$cookies" -c "$cookies" -o "$form1" "$restart_url"

# Request 2: If there's no form, fetch again (should end up with a login form).
if ! grep -q 'name="nonce"' "$form1"; then
  curl -b "$cookies" -c "$cookies" -o "$form1" "$restart_url"
fi

nonce=`find_nonce "$form1"`
echo "nonce is: $nonce"

# Request 3: We hit the login page, so we need to login first.
md5pass=`get_md5 "$ACCESS_CODE$nonce"`
curl -b "$cookies" -c "$cookies" -o "$form2" -L \
  --header "Referer: $restart_url" \
  --data "nonce=$nonce&password=**********&hashpassword=$md5pass&Continue=Continue" \
  "$login_url"

nonce=`find_nonce "$form2"`
echo "nonce is: $nonce"

# Request 4: Finally, restart.
curl -b "$cookies" -c "$cookies" -L "$done" \
  --header "Referer: $restart_url" \
  --data "nonce=$nonce&Restart=Restart" \
  "$restart_url"

grep 'Restarting' "$done" || {
  echo "The router at $ROUTER doesn't seem to be restarting. Please check /tmp/att-router-reboot-*.txt to see what's going on."
  exit 1
}
