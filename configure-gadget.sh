#!/bin/bash
# setup_gadget_mode.sh - Script to configure USB gadget mode on a Raspberry Pi SD card

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Check if SD card boot partition is provided
if [ $# -lt 1 ]; then
  echo "Usage: $0 /path/to/sd_card_boot_partition"
  exit 1
fi

BOOT_PARTITION=$1

# Verify the boot partition exists
if [ ! -d "$BOOT_PARTITION" ]; then
  echo "Error: Boot partition not found at $BOOT_PARTITION"
  exit 1
fi

echo "Configuring USB gadget mode on $BOOT_PARTITION..."

# Modify config.txt to enable dwc2 overlay
CONFIG_FILE="$BOOT_PARTITION/config.txt"
if [ -f "$CONFIG_FILE" ]; then
  if ! grep -q "dtoverlay=dwc2" "$CONFIG_FILE"; then
    echo "Adding dtoverlay=dwc2 to config.txt..."
    echo "dtoverlay=dwc2" >> "$CONFIG_FILE"
  else
    echo "dtoverlay=dwc2 already exists in config.txt"
  fi
else
  echo "Error: config.txt not found in boot partition"
  exit 1
fi

# Modify cmdline.txt to load required modules
CMDLINE_FILE="$BOOT_PARTITION/cmdline.txt"
if [ -f "$CMDLINE_FILE" ]; then
  if ! grep -q "modules-load=dwc2,g_ether" "$CMDLINE_FILE"; then
    echo "Adding modules-load=dwc2,g_ether to cmdline.txt..."
    sed -i 's/$/ modules-load=dwc2,g_ether/' "$CMDLINE_FILE"
  else
    echo "modules-load=dwc2,g_ether already exists in cmdline.txt"
  fi
else
  echo "Error: cmdline.txt not found in boot partition"
  exit 1
fi

# Create empty ssh file to enable SSH
SSH_FILE="$BOOT_PARTITION/ssh"
if [ ! -f "$SSH_FILE" ]; then
  echo "Creating empty ssh file to enable SSH..."
  touch "$SSH_FILE"
else
  echo "SSH already enabled"
fi

echo "USB gadget mode configuration complete!"
echo "Now you can insert the SD card into your Raspberry Pi and boot it."
echo "After booting, you should be able to connect via: ssh ink@inky.local"
echo "Default password: inkycamera"
