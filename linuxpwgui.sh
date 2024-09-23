#!/bin/bash
export NO_AT_BRIDGE=1
titl="LinuxPw-gui"
backupid=$RANDOM
imgicon="/usr/share/icons/hicolor/128x128/apps/linuxpwgui.png"
PART_LIST=$(lsblk -nro NAME,TYPE,FSTYPE | grep -iw part | awk -F" " '$3 ~ /ext[34]|btrfs|xfs/ {print $1}')
TESTMOUNT="/tmp/linux_test"
LINUX_INDICATOR="/etc/shadow"
cleanup() {
if [ -n "$MOUNT_POINT" ] && mountpoint -q "$MOUNT_POINT"; then
umount "$MOUNT_POINT" || echo "Erreur lors du démontage de $MOUNT_POINT"
fi
[ -d "$TESTMOUNT" ] && rmdir "$TESTMOUNT"
}
trap cleanup EXIT
if [ -z "$PART_LIST" ]; then
yad --center --error --title="$titl" --window-icon="$imgicon" --image="$imgicon" \
--width=500 --height=200 --text="Could not find any supported Linux partitions." --button="Quit:0"
exit 1
fi
[ ! -e "$TESTMOUNT" ] && mkdir $TESTMOUNT
LINUX_PARTITIONS=""
for LINUX_CHECK in $PART_LIST; do
if grep -wq $LINUX_CHECK /proc/mounts; then
MOUNT_POINT=$(lsblk -n -r -o MOUNTPOINT /dev/$LINUX_CHECK)
[ -e "$MOUNT_POINT/$LINUX_INDICATOR" ] && LINUX_PARTITIONS="${LINUX_PARTITIONS} $LINUX_CHECK"
else
if mount -o ro /dev/$LINUX_CHECK $TESTMOUNT; then
[ -e "$TESTMOUNT/$LINUX_INDICATOR" ] && LINUX_PARTITIONS="${LINUX_PARTITIONS} $LINUX_CHECK"
umount $TESTMOUNT
fi
fi
done
if [ -z "$LINUX_PARTITIONS" ]; then
yad --center --error --title="$titl" --window-icon="$imgicon" --image="$imgicon" --width=500 --height=200 \
--text="<b>Error</b>: No Linux installation found\n\nLinux partitions were found, but no valid Linux system was detected.\n"
exit 1
fi
COMBINED_LIST=""
for PARTITION in $LINUX_PARTITIONS; do
UUID=$(lsblk -n -r -o UUID /dev/$PARTITION)
LABEL=$(lsblk -n -r -o LABEL /dev/$PARTITION)
SIZE=$(lsblk -n -r -o SIZE /dev/$PARTITION)
COMBINED_LIST+="/dev/$PARTITION $SIZE, $LABEL $UUID\n"
done
SELECTED=$(echo -e "$COMBINED_LIST" | yad --center --list --title="$titl" --window-icon="$imgicon" --image="$imgicon" \
--text="Please choose the Linux installation\nto change user passwords:" \
--column="Linux Installation detected" \
--width=700 --height=400 \
--button="Cancel:1" --button="OK:0")
[ $? -ne 0 ] && exit 1
PARTITION=$(echo $SELECTED | cut -d'/' -f3 | cut -d' ' -f1)
if grep -wq $PARTITION /proc/mounts; then
MOUNT_POINT=$(lsblk -n -r -o MOUNTPOINT /dev/$PARTITION)
else
MOUNT_POINT=$TESTMOUNT
mount /dev/$PARTITION $MOUNT_POINT || {
yad --center --error --title="$titl" --window-icon="$imgicon" --image="$imgicon" \
--text="Failed to mount /dev/$PARTITION. Exiting." --button="OK:0"
exit 1
}
fi
while true; do
USER_LIST=$(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' "$MOUNT_POINT/etc/passwd")
USER_SELECTED=$(echo -e "$USER_LIST" | yad --center --list --title="$titl" --window-icon="$imgicon" --image="$imgicon" \
--text="Select the user to change the password:" \
--column="User" --width=300 --height=400 \
--button="Cancel:1" --button="OK:0")
if [ $? -ne 0 ] || [ -z "$USER_SELECTED" ]; then
break
fi
USER_SELECTED=$(echo "$USER_SELECTED" | sed 's/|//g')
while true; do
NEW_PASSWORD=$(yad --center --entry --title="$titl" --window-icon="$imgicon" --image="$imgicon" \
--text="Enter a new password for user '$USER_SELECTED':" --hide-text \
--width=400 --height=200)
if [ $? -ne 0 ]; then
break
fi
if [ -z "$NEW_PASSWORD" ]; then
yad --center --error --title="$titl" --window-icon="$imgicon" --image="$imgicon" \
--text="Password cannot be empty. Please enter a valid password." --button="OK:0"
continue
fi
CONFIRM_PASSWORD=$(yad --center --entry --title="$titl" --window-icon="$imgicon" --image="$imgicon" \
--text="Confirm the new password for user '$USER_SELECTED':" --hide-text \
--width=400 --height=200)
if [ $? -ne 0 ]; then
break
fi
if [ "$NEW_PASSWORD" != "$CONFIRM_PASSWORD" ]; then
yad --center --error --title="$titl" --window-icon="$imgicon" --image="$imgicon" \
--text="Passwords do not match. Please try again." --button="OK:0"
continue
fi
if echo "$USER_SELECTED:$NEW_PASSWORD" | chroot "$MOUNT_POINT" chpasswd; then
yad --center --title="$titl" --window-icon="$imgicon" --image="$imgicon" \
--text="Password for user '$USER_SELECTED' has been reset." --button="OK:0"
break 2
else
yad --center --error --title="$titl" --window-icon="$imgicon" --image="$imgicon" \
--text="Failed to change password. Please try again." --button="OK:0"
fi
done
done
