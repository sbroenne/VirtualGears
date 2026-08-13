#!/bin/bash
# Measures how a real KICKR responds, so the app's timing rules can be checked
# against the trainer instead of assumed.
PRODUCT="kickr-probe"
BUNDLE="KickrProbe"
DESCRIPTION="kickr-probe connects to a KICKR to measure how it responds."
SENTINEL="kickr-probe finished"
source "$(dirname "${BASH_SOURCE[0]}")/../run-tool.sh"
