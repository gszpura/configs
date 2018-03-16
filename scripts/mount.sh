dev=`sudo fdisk -l | grep "FAT32" | cut -d' ' -f1`
sudo mkdir -p /media/greg/usb1
sudo mount $dev /media/greg/usb1
echo "Mounted $dev at: /media/greg/usb1"
ln -s /media/greg/usb1 ~/usb
echo "Linked to ~/usb"
ls -la /media/greg/usb1
