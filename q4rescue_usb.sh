#!/bin/bash
workdir=$1
export NO_AT_BRIDGE=1
largeurecran=$(xrandr -q | grep -w Screen | sed 's/.*current //;s/,.*//' | awk '{print $1}')
hauteurecran=$(xrandr -q | grep -w Screen | sed 's/.*current //;s/,.*//' | awk '{print $3}')
pointX=$(echo $((($largeurecran-700)/2)))

get_usb_devices() {
local devices=()
while IFS= read -r line; do
devices+=("$line")
done < <(lsblk -ndo NAME,SIZE,TYPE,TRAN | awk '$3=="disk" && $4=="usb" {print $1 " (" $2 ")"}')
local options=""
for device in "${devices[@]}"; do
options+="!$device"
done
echo "$options"
}

get_device_size_gb() {
local device=$1
lsblk -bndo SIZE /dev/$device | awk '{ printf "%.1f\n", $1 / (1024*1024*1024) }'
}

calculate_persistence() {
local dsize=$1
local isosz=$2
echo "scale=1; $dsize - $isosz" | bc
}

calculate_remaining_space() {
local device_size=$1
local reqsz=$2
local persistence=$3
echo "scale=1; $device_size - $persistence - $reqsz" | bc
}

function ask_for_password() {
pointY=$(echo $((($hauteurecran-150)/2)))
passwd=$("$workdir/yad" --title="Authentication" \
--height=150 \
--fixed --geometry="+$pointX+$pointY" \
--window-icon="$workdir/q4rescueusb.png" \
--image="$workdir/q4rescueusb_banner.png" \
--image-on-top \
--form \
--field="<b>Admin privileges are needed to write to USB device:</b>:LBL" "" \
--field="Please enter your password::H" "" \
--hide-text \
--button="OK:0" --button="Cancel:1")

if [ $? -eq 1 ]; then
echo "Operation cancelled by the user."
exit 1
fi

passwd=$(echo "$passwd" | sed 's/^|//;s/|$//')
}

function test_root() {
sudo -n true 2>/dev/null
return $?
}

titl="q4rescue usb creator"

while true; do
pointY=$(echo $((($hauteurecran-300)/2)))
result=$("$workdir/yad" --title="$titl" \
  --height=300 \
  --fixed --geometry="+$pointX+$pointY" \
  --window-icon="$workdir/q4rescueusb.png" \
  --image="$workdir/q4rescueusb_banner.png" \
  --image-on-top \
  --text="" \
--form \
  --field="<b>Select options for creating the q4rescue bootable USB drive:</b>:LBL" "" \
  --field="USB Device:CB" "$(get_usb_devices)" \
  --field="q4rescue ISO location:FL" --file-filter \*.iso "/default/path/iso.q4rescue" \
  --field="Create persistence partition:CHK" "FALSE" \
  --field="Format remaining space:CHK" "FALSE" \
  --field="Format type for remaining space:CB" "exfat!fat32!ntfs!ext4" \
  --button="Refresh devices:2" --button="Quit:1" --button="Next:0")

ret=$?

case $ret in
1) 
exit 1
;;
2) 
continue
;;
252) 
exit 1
;;
esac

IFS='|' read -r select_options device iso_path create_persistence format_remaining filesystem <<< "$result"

device=$(echo "$device" | xargs)
device=$(echo "$device" | awk -F' ' '{print $1}')
iso_path=$(echo "$iso_path" | xargs)
create_persistence=$(echo "$create_persistence" | xargs)
format_remaining=$(echo "$format_remaining" | xargs)
filesystem=$(echo "$filesystem" | xargs)

if [ "$device" = "(null)" ] || [ -z "$device" ]; then
pointY=$(echo $((($hauteurecran-200)/2)))
"$workdir/yad" --title="$titl" \
--height=200 \
--fixed --geometry="+$pointX+$pointY" \
--window-icon="$workdir/q4rescueusb.png" \
--image="$workdir/q4rescueusb_banner.png" \
--image-on-top \
--form \
--field="\n\n  Please select a USB device.\n\n:LBL" "" \
--button="OK"
	continue
fi

if [ "$iso_path" = "/default/path/iso.q4rescue" ]; then
pointY=$(echo $((($hauteurecran-200)/2)))
"$workdir/yad" --title="$titl" \
--height=200 \
--fixed --geometry="+$pointX+$pointY" \
--window-icon="$workdir/q4rescueusb.png" \
--image="$workdir/q4rescueusb_banner.png" \
--image-on-top \
--form \
--field="\n\n  Please select a valid q4rescue ISO file.\n\n:LBL" "" \
--button="OK"
continue
fi

device_size=$(get_device_size_gb $device)
iso_size=$(du -b "$iso_path" | awk '{printf "%.1f", $1 / 1024 / 1024 / 1024}')
required_size=$(echo "$iso_size + 0.2" | bc)

if (( $(echo "$device_size < $required_size" | bc -l) )); then
pointY=$(echo $((($hauteurecran-200)/2)))
"$workdir/yad" --window-icon="$workdir/q4rescueusb.png" \
--title="$titl" \
--height=200 \
--fixed --geometry="+$pointX+$pointY" \
--image="$workdir/q4rescueusb_banner.png" \
--image-on-top \
--form \
--field="":LBL \
--field="<b>The selected device is too small.</b>:LBL" \
--field="\nRequired size: $required_size Gb\nDevice size: $device_size Gb\n:LBL" \
--button="OK:0"
continue
fi

persistence=0
if [ "$create_persistence" = "TRUE" ]; then
persistence_max=$(calculate_persistence $device_size $required_size)
persistence_prop=$(echo "scale=1; $persistence_max / 2" | bc)

pointY=$(echo $((($hauteurecran-350)/2)))
persistence_result=$("$workdir/yad" --window-icon="$workdir/q4rescueusb.png" \
--title="$titl" \
--height=350 \
--fixed --geometry="+$pointX+$pointY" \
--image="$workdir/q4rescueusb_banner.png" \
--image-on-top \
--form \
--field="<b>Configure persistence partition:</b>:LBL" "" \
--field="\nTotal device size: $device_size Gb\nq4rescue ISO size: $iso_size Gb\nMax. possible size for persistence: $persistence_max Gb\n:LBL" "" \
--field="Size of persistence partition (Gb):NUM" "$persistence_prop!0.0..$persistence_max!0.1!1" \
--button="Modify:1" --button="Next:0")

if [ $? -ne 0 ]; then
continue
fi

persistence=$(echo "$persistence_result" | tr ',' '.' | awk -F'|' '{print $3}')

if [[ ! "$persistence" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
echo "Invalid persistence size: $persistence"
exit 1
fi

fi

remaining_space=$(calculate_remaining_space $device_size $required_size $persistence )

if [ "$format_remaining" = "TRUE" ]; then
default_name="DATA"

while true; do
pointY=$(echo $((($hauteurecran-200)/2)))
partition_name_result=$("$workdir/yad" --window-icon="$workdir/q4rescueusb.png" \
--title="Partition Name" \
--height=200 \
--fixed --geometry="+$pointX+$pointY" \
--image="$workdir/q4rescueusb_banner.png" \
--image-on-top \
--form \
--field="<b>Enter the name for the $filesystem partition:</b>:LBL" "" \
--field="Partition Name:TXT" "$default_name" \
--button="OK:0")

ret=$?

if [ $ret -eq 0 ]; then
	partition_name=$(echo "$partition_name_result" | sed 's/^|//;s/|$//')
	if [ -z "$partition_name" ]; then
	pointY=$(echo $((($hauteurecran-150)/2)))
	"$workdir/yad" --window-icon="$workdir/q4rescueusb.png" \
	--title="Error" \
	--height=150 \
	--fixed --geometry="+$pointX+$pointY" \
	--image="$workdir/q4rescueusb_banner.png" \
	--image-on-top \
	--form \
	--field="<b>The partition name cannot be empty. Please enter a valid name.</b>:LBL" "" \
	--button="OK:0"
	continue
	else
	break
	fi
else
	echo "Operation cancelled or failed."
	exit 1
fi
done
fi


if [ "$create_persistence" = "TRUE" ]; then
persistence_info="- Create persistence partition: Yes\n   Persistence size: $persistence Gb"
else
persistence_info="- No persistence partition"
fi

if [ "$format_remaining" = "TRUE" ]; then
remaining_info="- format remaining space: $remaining_space Gb ($filesystem) - label: $partition_name"
else
remaining_info="- do nothing ($remaining_space Gb unformatted)"
fi

warnmsg="\n\n <span foreground='#BB0000'><b>  ** your device will be <u>wiped</u>,\n     so make sure it doesn't contain valuable data first. **</b></span>"

device_info="<b>Device:</b> $device  ($device_size Gb)"
iso_info="<b>ISO file:</b> $iso_path ($iso_size Gb)"
persistence_info="<b>Persistence:</b> $persistence_info"
remaining_info="<b>Remaining space:</b> $remaining_info"
warnmsg="<b>Warning!!</b> $warnmsg"

pointY=$(echo $((($hauteurecran-350)/2)))
summary=$("$workdir/yad" --title="$titl" \
--height=350 \
--fixed --geometry="+$pointX+$pointY" \
--window-icon="$workdir/q4rescueusb.png" \
--image="$workdir/q4rescueusb_banner.png" \
--image-on-top \
--form \
--field="<b>Summary of selected parameters:</b>:LBL" "" \
--field="$device_info:LBL" "" \
--field="$iso_info:LBL" "" \
--field="$persistence_info:LBL" "" \
--field="$remaining_info:LBL" "" \
--field="$warnmsg:LBL" "" \
--button="Modify:1" --button="Proceed:0")

if [ $? -ne 0 ]; then
continue
fi

break
done

yad_progress() {
echo "$2"
echo "# $1"
}

convert_gb_to_mb() {
local gb=$1
echo "scale=0; ($gb * 1024 + 0.5)/1" | bc
}

required_size_mb=$(convert_gb_to_mb $required_size)
persistence_mb=$(convert_gb_to_mb $persistence)

##########################################
while ! test_root; do
ask_for_password
if echo "$passwd" | sudo -S true 2>/dev/null; then
if test_root; then
break
fi
fi
pointY=$(echo $((($hauteurecran-150)/2)))
"$workdir/yad" --title="Error" \
--height=150 \
--fixed --geometry="+$pointX+$pointY" \
--window-icon="$workdir/q4rescueusb.png" \
--image="$workdir/q4rescueusb_banner.png" \
--image-on-top \
--form \
--field="<b>Invalid password. Please try again:</b>:LBL" "" \
--button="OK:0"
done


pointY=$(echo $((($hauteurecran-150)/2)))
(
yad_progress "Unmounting any mounted partitions on /dev/$device" 10
for part in $(lsblk -ln -o NAME /dev/$device | grep -v "^${device}$"); do
sudo umount -l /dev/$part > /dev/null 2>&1
done
sudo umount -l /mnt/isoq4r > /dev/null 2>&1
sudo umount -l /mnt/flashq4 > /dev/null 2>&1

yad_progress "Deleting existing partitions on /dev/$device" 15

sudo systemctl stop systemd-udevd-control.socket > /dev/null 2>&1
sudo systemctl stop systemd-udevd-kernel.socket > /dev/null 2>&1
sudo systemctl stop systemd-udevd.service > /dev/null 2>&1

sudo wipefs -o 1K -p /dev/$device > /dev/null 2>&1
sudo wipefs --all /dev/$device > /dev/null 2>&1
for offset in $(sudo wipefs -o 1K -p /dev/$device | awk '{print $5}'); do
sudo dd if=/dev/zero of=/dev/$device bs=512 seek=$((offset/512)) count=10
done
sudo sgdisk --zap-all /dev/$device > /dev/null 2>&1

sleep 2
sudo partprobe /dev/$device > /dev/null 2>&1
sleep 1

yad_progress "Creating FAT32 partition for q4rescue files" 20
sudo parted /dev/$device --script -- mklabel msdos
sudo parted -s /dev/$device mkpart primary fat32 1MiB ${required_size_mb}MiB
sudo parted -s /dev/$device set 1 boot on
sleep 5
sudo partprobe /dev/$device > /dev/null 2>&1
sleep 2

if [ ! -b /dev/${device}1 ]; then
"$workdir/yad" --window-icon="$workdir/q4rescueusb.png" --title="$titl" --error --text="Partition /dev/${device}1 was not created successfully. Please check the device and try again."
exit 1
fi

sudo mkfs.fat -F32 -v -I -n "Q4RESCUE" /dev/${device}1
sleep 1

yad_progress "Creating mount points" 25
sudo mkdir -p /mnt/flashq4 > /dev/null 2>&1
sudo mkdir -p /mnt/isoq4r > /dev/null 2>&1
sleep 1

yad_progress "Mounting /dev/${device}1" 30
sudo mount /dev/${device}1 /mnt/flashq4 > /dev/null 2>&1
yad_progress "Mounting ISO file $iso_path" 35
sudo mount -o loop "$iso_path" /mnt/isoq4r > /dev/null 2>&1

yad_progress "Copying ISO contents to USB device" 40
sudo rsync -a --exclude='live' /mnt/isoq4r/ /mnt/flashq4/
yad_progress "Copying ISO contents to USB device" 45
sudo rsync -a /mnt/isoq4r/live /mnt/flashq4/

yad_progress "Installing GRUB bootloader" 60
sudo mkdir -p /mnt/flashq4/EFI/BOOT
sudo grub-install --removable --boot-directory=/mnt/flashq4/boot --efi-directory=/mnt/flashq4/ /dev/$device > /dev/null 2>&1
sleep 1

yad_progress "Unmounting and cleaning mountpoints" 65
sudo umount -l /mnt/isoq4r > /dev/null 2>&1
sleep 2
sudo umount -l /mnt/flashq4 > /dev/null 2>&1
sleep 5
sudo rm -rf /mnt/isoq4r /mnt/flashq4 > /dev/null 2>&1
sudo umount -l /dev/${device}1 > /dev/null 2>&1
sleep 2

if [ "$create_persistence" = "TRUE" ]; then
sleep 1
yad_progress "Creating persistence partition" 70
sudo parted -s /dev/$device mkpart primary ext4 ${required_size_mb}MiB $((required_size_mb + persistence_mb))MiB
sleep 2
sudo partprobe /dev/$device > /dev/null 2>&1
sleep 1
sudo umount -l /dev/${device}2 > /dev/null 2>&1
sleep 1

yad_progress "Formatting persistence partition" 75
sudo mkfs.ext4 /dev/${device}2 > /dev/null 2>&1
sleep 1
yad_progress "Assigning label 'persistence' to the persistence partition" 80
sudo e2label /dev/${device}2 "persistence" > /dev/null 2>&1
fi


sudo mkdir -p /mnt/persist
sudo mount /dev/${device}2 /mnt/persist > /dev/null 2>&1
yad_progress "Configuring persistence partition" 85
echo '/ union' | sudo tee -a /mnt/persist/persistence.conf > /dev/null
sleep 1
sudo umount -l /dev/${device}2 > /dev/null 2>&1
sleep 5

if [ "$format_remaining" = "TRUE" ]; then
sleep 1
yad_progress "Creating data partition" 90
if [ "$create_persistence" = "TRUE" ]; then
start_mb=$((required_size_mb + persistence_mb))
data_dev="/dev/${device}3"
else
start_mb=$required_size_mb
data_dev="/dev/${device}2"
fi
sudo parted -s /dev/$device mkpart primary ${start_mb}MiB 100%
sleep 5
sudo partprobe /dev/$device
sleep 2

yad_progress "Formatting $filesystem data partition ($partition_name)" 95
case "$filesystem" in
fat32)
sudo mkfs.fat -F 32 -n "$partition_name" "$data_dev"
;;
exfat)
sudo mkfs.exfat -L "$partition_name" "$data_dev"
;;
ntfs)
sudo mkfs.ntfs -f -L "$partition_name" "$data_dev"
;;
ext4)
sudo mkfs.ext4 -L "$partition_name" "$data_dev"
;;
esac
fi

sudo systemctl start systemd-udevd.service
sudo systemctl start systemd-udevd-control.socket
sudo systemctl start systemd-udevd-kernel.socket

#echo "100" ; sleep 1
yad_progress "Completed." 100

) | "$workdir/yad" --title="$titl" \
--height=150 \
--fixed --geometry="+$pointX+$pointY" \
--window-icon="$workdir/q4rescueusb.png" \
--image="$workdir/q4rescueusb_banner.png" \
--image-on-top \
--progress \
--auto-kill \
--auto-close \
--text="" \
--percentage=0


end=$("$workdir/yad" --title="$titl" \
--height=150 \
--fixed --geometry="+$pointX+$pointY" \
--window-icon="$workdir/q4rescueusb.png" \
--image="$workdir/q4rescueusb_banner.png" \
--image-on-top \
--form \
--field="<b>Bootable USB drive created successfully!</b>:LBL" "" \
--button="OK:0")

#rm -rf "$workdir"
exit
