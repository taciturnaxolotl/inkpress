### Installing and Setting Up the Camera Server

First, ensure you have the camera module enabled and working:

```bash
rpicam-still -o image.jpg 
```

Next, create the camera service file:

```bash
sudo vi /etc/systemd/system/camera.service
```

Create a directory for storing photos:

```bash
mkdir photos
```

Install required Python packages:

```bash
sudo apt update
sudo apt install python3-picamera2
sudo apt install python3-websockets
```

Finally start the camera service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable camera.service
sudo systemctl start camera.service
```

You can check the status with:

```bash
sudo systemctl status camera
```

Or run the camera server directly with:

```bash
python3 camera_server.py
```
