import RPi.GPIO as GPIO
import time
from picamera2 import Picamera2
from datetime import datetime
import os
import logging
import http.server
import socketserver
import threading

# Setup logging
logger = logging.getLogger('camera_server')
logger.setLevel(logging.INFO)
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
file_handler = logging.FileHandler('/home/kierank/camera_server.log')
file_handler.setFormatter(formatter)
stream_handler = logging.StreamHandler()
stream_handler.setFormatter(formatter)
logger.addHandler(file_handler)
logger.addHandler(stream_handler)

class Config:
    BUTTON_PIN = 17
    PHOTO_DIR = "/home/kierank/photos"
    WEB_PORT = 80
    PHOTO_RESOLUTION = (2592, 1944)
    CAMERA_SETTLE_TIME = 1
    DEBOUNCE_DELAY = 0.2
    POLL_INTERVAL = 0.01

def validate_photo_dir():
    if not os.path.isabs(Config.PHOTO_DIR):
        raise ValueError("PHOTO_DIR must be an absolute path")
    if not os.access(Config.PHOTO_DIR, os.W_OK):
        raise PermissionError(f"No write access to {Config.PHOTO_DIR}")

# Ensure photo directory exists and is valid
validate_photo_dir()
os.makedirs(Config.PHOTO_DIR, exist_ok=True)

# Set up GPIO
GPIO.setmode(GPIO.BCM)
GPIO.setup(Config.BUTTON_PIN, GPIO.IN, pull_up_down=GPIO.PUD_UP)

# Create a simple HTML gallery template - using triple quotes properly
HTML_TEMPLATE = """<!DOCTYPE html>
<html>
<head>
    <title>Inkpress: Gallery</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body {{ font-family: Arial; max-width: 800px; margin: 0 auto; padding: 20px; }}
        h1 {{ text-align: center; }}
        .gallery {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 10px; }}
        .photo {{ border: 1px solid #ddd; padding: 5px; }}
        .photo img {{ width: 100%; height: auto; }}
        .photo a {{ display: block; text-align: center; margin-top: 5px; }}
        button {{ display: block; margin: 10px auto; padding: 5px 10px; }}
    </style>
</head>
<body>
    <h1>Inkpress: Gallery</h1>
    <button onclick="location.reload()">Refresh Gallery</button>
    <div class="gallery">
        {photo_items}
    </div>
</body>
</html>
"""

class PhotoHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=Config.PHOTO_DIR, **kwargs)

    def do_GET(self):
        if self.path == '/':
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('X-Frame-Options', 'DENY')
            self.send_header('X-XSS-Protection', '1; mode=block')
            self.end_headers()

            # Generate photo gallery HTML
            photo_items = ""
            try:
                files = sorted(os.listdir(Config.PHOTO_DIR), reverse=True)
                for filename in files:
                    if filename.lower().endswith(('.jpg', '.jpeg', '.png')):
                        timestamp = filename.replace('photo_', '').replace('.jpg', '')
                        photo_items += f"""
                        <div class="photo">
                            <img src="/{filename}" alt="{timestamp}">
                            <a href="/{filename}" download>Download</a>
                        </div>
                        """

                if not photo_items:
                    photo_items = "<p style='grid-column: 1/-1; text-align: center;'>No photos yet. Press the button to take a photo!</p>"
            except Exception as e:
                logger.error(f"Error generating gallery: {str(e)}")
                photo_items = f"<p>Error loading photos: {str(e)}</p>"

            html = HTML_TEMPLATE.format(photo_items=photo_items)
            self.wfile.write(html.encode())
        else:
            super().do_GET()

def take_photo():
    """
    Captures a photo using the Raspberry Pi camera.

    The photo is saved with a timestamp in the configured photo directory.
    The camera is configured for still capture at the specified resolution.

    Raises:
        IOError: If there's an error accessing the camera or saving the file
    """
    try:
        with Picamera2() as picam2:
            config = picam2.create_still_configuration(main={"size": Config.PHOTO_RESOLUTION})
            picam2.configure(config)
            picam2.start()
            time.sleep(Config.CAMERA_SETTLE_TIME)

            timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
            filename = f"{Config.PHOTO_DIR}/photo_{timestamp}.jpg"
            logger.info(f"Taking photo: {filename}")

            picam2.capture_file(filename)
            logger.info("Photo taken successfully")
    except IOError as e:
        logger.error(f"IO Error while taking photo: {str(e)}")
    except Exception as e:
        logger.error(f"Unexpected error while taking photo: {str(e)}")

def run_server():
    try:
        handler = PhotoHandler
        with socketserver.TCPServer(("", Config.WEB_PORT), handler) as httpd:
            logger.info(f"Web server started at port {Config.WEB_PORT}")
            httpd.serve_forever()
    except Exception as e:
        logger.error(f"Server error: {str(e)}")

def main():
    logger.info("Camera and web server starting")
    server = None

    try:
        server = socketserver.TCPServer(("", Config.WEB_PORT), PhotoHandler)
        server_thread = threading.Thread(target=server.serve_forever, daemon=True)
        server_thread.start()

        previous_state = GPIO.input(Config.BUTTON_PIN)
        while True:
            current_state = GPIO.input(Config.BUTTON_PIN)

            if current_state == False and previous_state == True:
                logger.info("Button press detected")
                take_photo()
                time.sleep(Config.DEBOUNCE_DELAY)

            previous_state = current_state
            time.sleep(Config.POLL_INTERVAL)

    except KeyboardInterrupt:
        logger.info("Program stopped by user")
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
    finally:
        if server:
            server.shutdown()
            server.server_close()
        GPIO.cleanup()
        logger.info("GPIO cleaned up")

if __name__ == "__main__":
    main()
