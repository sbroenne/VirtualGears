#!/bin/bash
# Pretends to be a trainer so a real riding app can be watched, and reports
# what it sent.
PRODUCT="app-tap"
BUNDLE="AppTap"
DESCRIPTION="app-tap pretends to be a trainer so a riding app can be watched."
SENTINEL="app-tap finished"
source "$(dirname "${BASH_SOURCE[0]}")/../run-tool.sh"
