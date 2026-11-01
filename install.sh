#!/bin/sh
# Install the Claude Usage plasmoid, or update an existing install in place.
#
# Updates copy files over the installed package rather than using
# `kpackagetool6 --upgrade`, which makes Plasma treat the widget as removed
# and drop it from the system tray / panel.
set -e
cd "$(dirname "$0")"

ID=org.hodglim.claudeusage
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/$ID"

if [ -d "$DEST" ]; then
    cp -r package/. "$DEST/"
    echo "Updated $DEST"
    echo "Restart Plasma to load the changes: systemctl --user restart plasma-plasmashell"
else
    kpackagetool6 -t Plasma/Applet -i package
    echo "Installed. Now add 'Claude Usage' to your system tray or panel (see README)."
fi
