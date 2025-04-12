import RPi.GPIO as GPIO
import time
from picamera2 import Picamera2
from datetime import datetime
import os
import logging
import http.server
import socketserver
import threading
import websockets
import asyncio

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
    WS_PORT = 8765
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

# WebSocket clients set
connected_clients = set()

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
        .photo .actions {{ text-align: center; margin-top: 5px; }}
        .photo .actions a {{ margin: 0 5px; }}
    </style>
    <script>
        const ws = new WebSocket('ws://' + window.location.hostname + ':8765');
        ws.onmessage = function(event) {{
            if(event.data === 'reload') {{
                window.location.reload();
            }}
        }};

        function deletePhoto(filename) {{
            if(confirm('Are you sure you want to delete this photo?')) {{
                fetch('/delete/' + filename, {{
                    method: 'POST'
                }}).then(response => {{
                    if(response.ok) {{
                        window.location.reload();
                    }}
                }});
            }}
        }}
    </script>
</head>
<body>
    <h1>Inkpress: Gallery</h1>
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
                            <div class="actions">
                                <a href="/{filename}" download>Download</a>
                                <a href="#" onclick="deletePhoto('{filename}'); return false;">Delete</a>
                            </div>
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

    def do_POST(self):
        if self.path.startswith('/delete/'):
            filename = self.path[8:]  # Remove '/delete/' prefix
            file_path = os.path.join(Config.PHOTO_DIR, filename)

            try:
                if os.path.exists(file_path) and os.path.isfile(file_path):
                    os.remove(file_path)
                    logger.info(f"Deleted photo: {filename}")
                    self.send_response(200)
                    self.send_header('Content-type', 'text/plain')
                    self.end_headers()
                    self.wfile.write(b"File deleted successfully")
                    asyncio.run(notify_clients())
                else:
                    self.send_response(404)
                    self.send_header('Content-type', 'text/plain')
                    self.end_headers()
                    self.wfile.write(b"File not found")
            except Exception as e:
                logger.error(f"Error deleting file {filename}: {str(e)}")
                self.send_response(500)
                self.send_header('Content-type', 'text/plain')
                self.end_headers()
                self.wfile.write(b"Error deleting file")
        else:
            self.send_response(404)
            self.end_headers()

async def websocket_handler(websocket, path):
    connected_clients.add(websocket)
    try:
        await websocket.wait_closed()
    finally:
        connected_clients.remove(websocket)

async def notify_clients():
    if connected_clients:
        await asyncio.gather(
            *[client.send('reload') for client in connected_clients]
        )

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

            # Notify websocket clients to reload
            asyncio.run(notify_clients())
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

def cleanup():
    try:
        # Instead of getting/creating a new loop, we'll work with the running loop
        loop = asyncio.get_running_loop()

        # Create a new event loop for cleanup operations if needed
        cleanup_loop = asyncio.new_event_loop()
        asyncio.set_event_loop(cleanup_loop)

        # Close all websocket connections
        for websocket in connected_clients.copy():
            cleanup_loop.run_until_complete(websocket.close())

        # Cancel all tasks in the main loop
        for task in asyncio.all_tasks(loop):
            task.cancel()

        cleanup_loop.close()

    except RuntimeError:
        # Handle case where there is no running loop
        logger.info("No running event loop found during cleanup")
    except Exception as e:
        logger.error(f"Error during cleanup: {str(e)}")

def main():
    logger.info("Camera and web server starting")
    server = None
    ws_server = None
    loop = None

    try:
        socketserver.TCPServer.allow_reuse_port = True

        # Start HTTP server
        server = socketserver.TCPServer(("", Config.WEB_PORT), PhotoHandler)
        server_thread = threading.Thread(target=server.serve_forever, daemon=True)
        server_thread.start()

        # Create new event loop for websockets
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)

        # Start WebSocket server
        ws_server = websockets.serve(websocket_handler, "0.0.0.0", Config.WS_PORT)
        loop.run_until_complete(ws_server)
        ws_thread = threading.Thread(
            target=loop.run_forever,
            daemon=True
        )
        ws_thread.start()

        logger.info("Camera and web server started")

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
        if loop:
            loop.stop()
        GPIO.cleanup()
        logger.info("GPIO cleaned up")
        cleanup()
        time.sleep(0.5)

if __name__ == "__main__":
    main()
