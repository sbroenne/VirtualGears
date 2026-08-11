#!/bin/bash
# Connects to the app on the phone the way a riding app on a PC does, and
# reports what it found.
PRODUCT="ride-sim"
BUNDLE="RideSim"
DESCRIPTION="ride-sim connects to the app as a riding app would, to check what it offers."
SENTINEL="ride-sim finished"
source "$(dirname "${BASH_SOURCE[0]}")/../run-tool.sh"
