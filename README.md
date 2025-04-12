# Inky

<img src="https://cachet.dunkirk.sh/emojis/inky/r/" width="130" align="right">

> ### More deets coming soon 👀  
> An open-source, eink-based, rpi zero 2 w powered camera.

## Setup

Put raspberry pi os lite 64-bit onto an SD card using the Raspberry Pi Imager and in the configureation step make sure to 1) add your SSH key and 2) set the user:password to `inky:inkycamera`. Oh and also make sure to add your wifi creds so we can update and install packages.

Next you need to configure network over usb so we can ssh in easily and be able to access the photo webserver.

Before sticking the card into the rpi, navigate to the boot partition and edit:

`config.txt` - add to bottom:
```txt
dtoverlay=dwc2
```

and `cmdline.txt` - apphend to the only line:
```txt
modules-load=dwc2,g_ether
```

Create empty `ssh` file in boot partition to enable SSH or just click the button in the RPI Imager gui.

now ssh in:
```bash
ssh ink@inkpress.local
# Default password: inkycamera
```

The firmware instructions are in [`src/README.md`](src/README.md)

### Troubleshooting
- Ensure you are using the DATA port, not power-only
- Some systems may need USB Ethernet gadget drivers

<p align="center">
	<img src="https://raw.githubusercontent.com/taciturnaxolotl/carriage/master/.github/images/line-break.svg" />
</p>

<p align="center">
	<i><code>&copy 2025-present <a href="https://github.com/taciturnaxolotl">Kieran Klukas</a></code></i>
</p>

<p align="center">
	<a href="https://github.com/taciturnaxolotl/inky/blob/master/LICENSE.md"><img src="https://img.shields.io/static/v1.svg?style=for-the-badge&label=License&message=MIT&logoColor=d9e0ee&colorA=363a4f&colorB=b7bdf8"/></a>
</p>
