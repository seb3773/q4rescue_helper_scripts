#!/bin/bash
#need root (sudo ...)

#tmppath=$(mktemp -d)
#extract yad+icon+parted
export NO_AT_BRIDGE=1

#determine if yad binary on the system,isyad=$(which yad) ;  if yes : yadcmd=$isyad ; if not yadcmd="$tmppath/yadL"
# dependencies: parted / sgdisk


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
passwd=$(yad --title="Authentication" --window-icon=q4rescueusb.png --text="\nAdmin privileges are needed to write to usb device\nPlease enter your password:" --entry --hide-text --button="OK:0" --button="Cancel:1")
if [ $? -eq 1 ]; then
echo "Operation cancelled by the user."
exit 1
fi
}

function test_root() {
sudo -n true 2>/dev/null
return $?
}

titl="q4rescue usb creator"

while true; do
    result=$(yad --title="$titl" --text="\n <span><b>Select options for creating the q4rescue bootable USB drive:</b></span>\n" \
    --width=700 \
    --height=300 \
    --window-icon=q4rescueusb.png \
    --image="q4rescueusb.png" \
    --form \
    --field="USB Device:CB" "$(get_usb_devices)" \
    --field="q4rescue ISO location:FL" --file-filter \*.iso "/default/path/iso.q4rescue" \
    --field="Create persistence partition:CHK" "FALSE" \
    --field="Format remaining space:CHK" "FALSE" \
    --field="      Format type for remaining space:CB" "fat32!exfat!ntfs!ext4" \
        --button="Refresh:2" --button="Quit:1" --button="Next:0")
# ajouter champ "Partition name for remaining space (optional):"
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

    IFS='|' read -r device iso_path create_persistence format_remaining filesystem <<< "$result"
    device=$(echo $device | cut -d' ' -f1)

    if [ "$device" = "(null)" ] || [ -z "$device" ]; then
        yad --title="$titl" --width=400 --height=100 --window-icon=q4rescueusb.png \
        --error --text="\n\n  Please select a USB device.\n\n"
        continue
    fi

if [ "$iso_path" = "/default/path/iso.q4rescue" ]; then
    yad --title="$titl" --width=400 --height=100 --window-icon=q4rescueusb.png \
    --error --text="\n\n  Please select a valid ISO file.\n\n"
    continue
fi

    device_size=$(get_device_size_gb $device)

iso_size=$(du -b "$iso_path" | awk '{printf "%.1f", $1 / 1024 / 1024 / 1024}')

required_size=$(echo "$iso_size + 0.2" | bc)

if (( $(echo "$device_size < $required_size" | bc -l) )); then
    yad --window-icon=q4rescueusb.png --title="$titl" --error \
    --image="q4rescueusb.png" \
--width=450 --height=80 \
    --text="\n\n  The selected device is too small.\n\n  - Required size: $required_size Gb\n  - Device size: $device_size Gb\n\n"
    continue
fi

#add crypting option
#persistcrypt=0

    persistence=0
    if [ "$create_persistence" = "TRUE" ]; then
        persistence_max=$(calculate_persistence $device_size $required_size)
persistence_prop=$(echo "scale=1; $persistence_max / 2" | bc)
        persistence_result=$(yad --window-icon=q4rescueusb.png \
    --image="q4rescueusb.png" \
 --width=600 --height=250 \
         --title="$titl" \
        --text="\n    <span><b>Configure persistence partition:</b></span>\n\n - Total device size: $device_size Gb\n - q4rescue ISO size: $iso_size Gb\n  > max. possible size for persistence: $persistence_max Gb\n\n" \
        --form \
        --field="Size of persistence partition (Gb):NUM" "$persistence_prop!0.0..$persistence_max!0.1!1" \
        --button="Modify:1" --button="Next:0")
#add encrypt persistence partition
        if [ $? -ne 0 ]; then
            continue
        fi

        persistence=$(echo $persistence_result | tr ',' '.' | sed 's/|$//')
    fi

    remaining_space=$(calculate_remaining_space $device_size $required_size $persistence )

if [ "$create_persistence" = "TRUE" ]; then
    persistence_info="- Create persistence partition: Yes\n   Persistence size: $persistence Gb"
else
    persistence_info="- No persistence partition"
fi

if [ "$format_remaining" = "TRUE" ]; then
    remaining_info="- Format remaining space: $remaining_space Gb ($filesystem)"
else
    remaining_info="- Remaining space: $remaining_space Gb (unformatted)"
fi

warnmsg="\n\n <span foreground='#BB0000'><b>  ** Warning: your device will be <u>wiped</u>,\n     so make sure it doesn't contain valuable data first. **</b></span>"

summary=$(yad --title="$titl" \
    --width=600 --window-icon=q4rescueusb.png \
    --image="q4rescueusb.png" --height=128 \
        --button="Modify:1" --button="Proceed:0" \
    --text="<b>Summary of selected parameters:</b>\n\n\n\
Device: $device  ($device_size Gb) \n\n\
ISO file: $iso_path ($iso_size Gb)\n\n\
$persistence_info\n\n\
$remaining_info\n\n\
$warnmsg" \
EOF
)



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


###############################################################################################################"""
while ! test_root; do
ask_for_password
if echo "$passwd" | sudo -S true 2>/dev/null; then
if test_root; then
break
fi
fi
yad --title="Error" --text="Invalid password. Please try again." --button="OK:0"
done


(
    yad_progress "Unmounting any mounted partitions on /dev/$device" 10
    for part in $(lsblk -ln -o NAME /dev/$device | grep -v "^${device}$"); do
        sudo umount -l /dev/$part
    done
#just in case
    sudo umount -l /mnt/isoq4r > /dev/null
    sudo umount -l /mnt/flashq4 > /dev/null

    yad_progress "Deleting existing partitions on /dev/$device" 20
sudo wipefs -af /dev/$device
sudo sgdisk --zap-all /dev/$device
    sleep 2
    sudo partprobe /dev/$device
    sleep 1

    yad_progress "Creating FAT32 partition for q4rescue files" 30
    sudo parted /dev/$device --script -- mklabel msdos
    sudo parted -s /dev/$device mkpart primary fat32 1MiB ${required_size_mb}MiB
    sudo parted -s /dev/$device set 1 boot on
    sleep 5
    sudo partprobe /dev/$device
    sleep 2

    if [ ! -b /dev/${device}1 ]; then
        yad --window-icon=q4rescueusb.png --title="$titl" --error --text="Partition /dev/${device}1 was not created successfully. Please check the device and try again."
        exit 1
    fi
    sudo mkfs.fat -F32 -v -I -n "Q4RESCUE" /dev/${device}1
    sleep 1

    yad_progress "Creating mount points" 40
    sudo mkdir -p /mnt/flashq4
    sudo mkdir -p /mnt/isoq4r
    sleep 1

    yad_progress "Mounting /dev/${device}1" 50
    sudo mount /dev/${device}1 /mnt/flashq4
    sleep 1

    yad_progress "Mounting ISO file $iso_path" 60
    sudo mount -o loop "$iso_path" /mnt/isoq4r
    sleep 1

    yad_progress "Copying ISO contents to USB device" 70
    sudo cp -r /mnt/isoq4r/. /mnt/flashq4
    sleep 1

    yad_progress "Installing GRUB bootloader" 80
    sudo mkdir -p /mnt/flashq4/EFI/BOOT
    sudo grub-install --removable --boot-directory=/mnt/flashq4/boot --efi-directory=/mnt/flashq4/ /dev/$device
    sleep 1

    yad_progress "Unmounting and cleaning mountpoints" 90
    sudo umount -l /mnt/isoq4r
    sleep 10
    sudo umount -l /mnt/flashq4
    sudo rm -rf /mnt/isoq4r /mnt/flashq4
    sudo umount -l /dev/${device}1
    sleep 5

    if [ "$create_persistence" = "TRUE" ]; then
        sleep 1
        yad_progress "Creating persistence partition" 95
        sudo parted -s /dev/$device mkpart primary ext4 ${required_size_mb}MiB $((required_size_mb + persistence_mb))MiB
        sleep 2
        sudo partprobe /dev/$device
        sleep 1
        sudo umount -l /dev/${device}2
        sleep 1

        yad_progress "Formatting persistence partition" 96
        sudo mkfs.ext4 /dev/${device}2
        sleep 1
        yad_progress "Assigning label 'persistence' to the persistence partition" 97
        sudo e2label /dev/${device}2 "persistence"
    fi

    sudo mkdir -p /mnt/persist
    sudo mount /dev/${device}2 /mnt/persist
    echo '/ union' | sudo tee -a /mnt/persist/persistence.conf > /dev/null
    sleep 1
    sudo umount -l /dev/${device}2
    sleep 5

    if [ "$format_remaining" = "TRUE" ]; then
        sleep 1
        yad_progress "Creating data partition" 98
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

        case "$filesystem" in
            fat32)
                sudo mkfs.fat -F 32 -n "Data" "$data_dev"
                ;;
            exfat)
                sudo mkfs.exfat -L "Data" "$data_dev"
                ;;
            ntfs)
                sudo mkfs.ntfs -f -L "Data" "$data_dev"
                ;;
            ext4)
                sudo mkfs.ext4 -L "Data" "$data_dev"
                ;;
        esac
    fi

    echo "100" ; sleep 1
    yad_progress "Completed." 100
) | yad --progress --auto-close --title="$titl" --width=400 --text="Creating q4rescue usb..." --percentage=0 --window-icon=q4rescueusb.png --image="q4rescueusb.png" --height=128

yad --window-icon=q4rescueusb.png --title="$titl" --info --text="Bootable USB drive created successfully!"