# Inky

![blueprint](https://raw.githubusercontent.com/taciturnaxolotl/inky/main/.github/images/blueprint.svg)

> ### More deets coming soon 👀  
> An open-source, eink-based, rpi zero 2 w powered camera.

## Setup

Put raspberry pi os lite 64-bit onto an SD card using the Raspberry Pi Imager and in the configureation step make sure to 1) add your SSH key and 2) set the user:password to `ink:inkycamera`. Oh and also make sure to add your wifi creds so we can update and install packages.

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
ssh ink@inky.local
# Default password: inkycamera
```

The firmware instructions are in [`src/README.md`](src/README.md) or you can run the following to auto configure

```bash
sudo bash -c "$(curl -fsSL hack.club/crgqvn)"
```

## Build Notes

This was a very fun project to work on because it felt so open ended. I did the case in [onshape](https://cad.onshape.com/documents/cf1e24c66f7dd61abebe0cb7/w/6aa471fe8ad6f1c116b0e667/e/df957c19e601178ca97da17b?renderMode=0&uiState=67fa0bb8d747ac4041a4fb55) and made it into as slim of a design as possible. The pretty blueprint was made by just taking an onshape drawing, swapping out the background color, changing all the line stroke colors to #D2E7F8, and then changing all the text fill to the same color.

The code is bundled into an iso that auto builds via github actions on release which makes it as simple as just flashing an sd card to get running.

## BOM

| Name | Price | Manufacturer/Buy Link |
|------|--------|---------------------|
| Mini to Standard Camera Adapter Cable - 38mm | $4.99 | [Vilros](https://vilros.com/products/mini-to-standard-camera-adapter-cable-22-way-0-5mm-pitch-15-way-1mm-pitch-for-raspberry-pi-5-and-zero?variant=40167348633694) |
| Raspberry Pi Zero 2 W | $15.00 | [Adafruit](https://www.adafruit.com/product/5291) |
| Raspberry Pi Camera Module - Standard (any version works) | $25.00 | [Adafruit](https://www.adafruit.com/product/5657) |

<p align="center">
	<img src="https://raw.githubusercontent.com/taciturnaxolotl/carriage/master/.github/images/line-break.svg" />
</p>

<p align="center">
	<i><code>&copy 2025-present <a href="https://github.com/taciturnaxolotl">Kieran Klukas</a></code></i>
</p>

<p align="center">
	<a href="https://github.com/taciturnaxolotl/inky/blob/master/LICENSE.md"><img src="https://img.shields.io/static/v1.svg?style=for-the-badge&label=License&message=MIT&logoColor=d9e0ee&colorA=363a4f&colorB=b7bdf8"/></a>
</p>
