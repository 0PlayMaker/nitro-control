#!/bin/sh
# Re-apply perms + saved state on resume (belt-and-suspenders; this machine
# holds health_mode through suspend, but reloads/quirks are covered here).
[ "$1" = "post" ] && /usr/local/bin/nitroctl boot-apply
exit 0
