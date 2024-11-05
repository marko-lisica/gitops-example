#!/bin/sh

# variables
APPDIR="/Applications/"
TMPDIR=$(dirname "$(realpath $INSTALLER_PATH)")

# install pkg files
sudo installer -pkg "$TMPDIR/Cloudflare_WARP_2024.9.346.0.pkg" -target /
