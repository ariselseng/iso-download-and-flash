# iso-download-and-flash
A script to download an iso image and flash it to device simultaneously. If you run the command later, it will ask you if it should use the local iso image already download or re-download.
Example:
```shell
./iso-download-and-flash.sh --url "https://releases.ubuntu.com/20.04.3/ubuntu-20.04.3-desktop-amd64.iso" --target ~/Downloads/ --device /dev/sda
```