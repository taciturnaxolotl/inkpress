#!/bin/bash
# inky_setup.sh - auto setup the inky server

# Check if this is being run from a file
if [ -f "$0" ]; then
  echo "Checking for updated setup script..."
  LATEST=$(curl -s https://raw.githubusercontent.com/taciturnaxolotl/inky/refs/heads/main/setup.sh)
  LATEST_HASH=$(echo "$LATEST" | sha256sum | cut -d' ' -f1)
  CURRENT_HASH=$(cat "$0" | sha256sum | cut -d' ' -f1)
  if [ $? -eq 0 ] && [ ! -z "$LATEST" ] && [ "$LATEST_HASH" != "$CURRENT_HASH" ]; then
    echo "Applying latest version..."
    echo "$LATEST" > "$0"
    exec "$0" "$@"
    exit 0
  fi
else
  echo "Creating setup script file..."
  curl -s https://raw.githubusercontent.com/taciturnaxolotl/inky/refs/heads/main/setup.sh > setup.sh
  chmod +x setup.sh
  exec ./setup.sh "$@"
  exit 0
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root or with sudo"
  exit 1
fi

echo "Setting up Inky camera server from GitHub repository..."

# Check for existing repository
cd /home/ink
if [ -d "/home/ink/inky" ]; then
  read -p "Repository already exists. Would you like to update it? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    cd /home/ink/inky
    git pull

    cp /home/ink/inky/src/camera_server.py /home/ink/ && chown ink:ink /home/ink/camera_server.py && chmod +x /home/ink/camera_server.py
    cp /home/ink/inky/src/eink-4gray.png /home/ink/ && chown ink:ink /home/ink/eink-4gray.png

    # Just restart the service since it's an update
    echo "Restarting camera service..."
    systemctl restart camera.service
  else
    echo "Okay, not updating"
    exit
  fi
else
  # Update system packages and install dependencies
  echo "Updating package lists and installing dependencies..."
  apt update
  apt install -y python3-picamera2 python3-websockets python3-rpi.gpio git imagemagick

  # Create directory for storing photos
  echo "Creating photos directory..."
  mkdir -p /home/ink/photos
  chown ink:ink /home/ink/photos

  git clone https://github.com/taciturnaxolotl/inky.git

  chown -R ink:ink /home/ink/inky

  # Copy camera_server.py to user's home directory
  echo "Setting up camera server..."
  cp /home/ink/inky/src/camera_server.py /home/ink/
  chown ink:ink /home/ink/camera_server.py
  chmod +x /home/ink/camera_server.py

  # copy dither palate
  cp /home/ink/inky/src/eink-4gray.png /home/ink/
  chown ink:ink /home/ink/eink-4gray.png

  # Copy and set up systemd service
  echo "Setting up systemd service..."
  cp /home/ink/inky/src/camera.service /etc/systemd/system/

  # Test the camera
  echo "Testing camera..."
  if command -v rpicam-still &> /dev/null; then
      mkdir -p /tmp/camera_test
      if rpicam-still -o /tmp/camera_test/test.jpg; then
          echo "Camera test successful!"
      else
          echo "Camera test failed. Please check your camera connection."
      fi
  else
      echo "rpicam-still not found. Please make sure the camera is properly enabled."
  fi

  # Enable and start the service
  echo "Enabling and starting camera service..."
  systemctl daemon-reload
  systemctl enable camera.service
  systemctl start camera.service
fi

echo "Setup complete!"
echo "Camera server should now be running."
echo "You can access the web interface at: http://inky.local"
echo "Check service status with: sudo systemctl status camera"
