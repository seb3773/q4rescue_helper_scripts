#!/bin/bash
export NO_AT_BRIDGE=1
titl="NTpw-gui"
backupid=$RANDOM

PART_LIST=$(lsblk -nro NAME,TYPE,FSTYPE | grep -iw part | awk -F" " '$3 ~ /./ {print $1}')

for NTFS_CHECK in $PART_LIST; do
FILESYSTEM=$(lsblk -n -r -o FSTYPE /dev/$NTFS_CHECK | tr '[:upper:]' '[:lower:]')
[ "$FILESYSTEM" = "ntfs" -o "$FILESYSTEM" = "ntfs-3g" ] && NTFS="${NTFS} $NTFS_CHECK"
done

[ -z "$NTFS" ] && yad --center --error  --title="$titl"  --window-icon="ntpwgui.png" --image="ntpwgui.png" --width=500 --height=200 --text="Could not find any supported NTFS partitions." --title="Error" && exit 1

TESTMOUNT="/tmp/windows_test"
WINNT="WINNT/system32/config/SAM"
WINXP="WINDOWS/system32/config/SAM"
WIN78="Windows/System32/config/SAM"
WINPATH="$WINNT $WINXP $WIN78"
WINHIVE="${WINNT/SAM/SOFTWARE} ${WINXP/SAM/SOFTWARE} ${WINXP/SAM/software} ${WIN78/SAM/SOFTWARE} ${WIN78/SAM/software}"

[ ! -e "$TESTMOUNT" ] && mkdir $TESTMOUNT
for WINDOWS_CHECK in $NTFS; do
if grep -wq $WINDOWS_CHECK /proc/mounts; then
MOUNT_POINT=$(lsblk -n -r -o MOUNTPOINT /dev/$WINDOWS_CHECK)
for FINDSAM in $WINPATH; do [ -e "$MOUNT_POINT/$FINDSAM" ] && WINDOWS="${WINDOWS} $WINDOWS_CHECK"; done
if ! grep -Ew "[[:lower:]]{2}_[[:upper:]]{2}" /proc/cmdline; then
for FINDSOFTW in $WINHIVE; do
[ -e "$MOUNT_POINT/$FINDSOFTW" ] &&
reglookup -H -p /Microsoft/Windows\ NT/CurrentVersion/ProductName "$MOUNT_POINT/$FINDSOFTW" | sed 's/,$//' |
awk -v p="$WINDOWS_CHECK" -F"," '{print p","$NF}' >>/tmp/winversions
done
fi
else
mount -o ro /dev/$WINDOWS_CHECK $TESTMOUNT
for FINDSAM in $WINPATH; do [ -e "$TESTMOUNT/$FINDSAM" ] && WINDOWS="${WINDOWS} $WINDOWS_CHECK"; done
if ! grep -Ew "[[:lower:]]{2}_[[:upper:]]{2}" /proc/cmdline; then
for FINDSOFTW in $WINHIVE; do
[ -e "$TESTMOUNT/$FINDSOFTW" ] &&
reglookup -H -p /Microsoft/Windows\ NT/CurrentVersion/ProductName "$TESTMOUNT/$FINDSOFTW" | sed 's/,$//' |
awk -v p="$WINDOWS_CHECK" -F"," '{print p","$NF}' >>/tmp/winversions
done
fi
umount $TESTMOUNT
fi
done
if [ -z "$WINDOWS" ]; then
yad --center --error  --title="$titl" --window-icon="ntpwgui.png"  --image="ntpwgui.png" --width=500 --height=200 \
--text="<b>Error</b>: No Windows installation found\n\nNTFS partitions were found, but no Windows SAM file was detected.\n\nMake sure you have a valid Windows installation.\n"
rm -f /tmp/winversions
exit 1
fi
#rmdir $TESTMOUNT

COMBINED_LIST=""
for PARTITION in $WINDOWS; do
[ -s /tmp/winversions ] && PRODNAME=", $(grep -w $PARTITION /tmp/winversions | awk -F, '{print $NF}')"
UUID=$(lsblk -n -r -o UUID /dev/$PARTITION)
LABEL=$(lsblk -n -r -o LABEL /dev/$PARTITION)
SIZE=$(lsblk -n -r -o SIZE /dev/$PARTITION)
COMBINED_LIST+="/dev/$PARTITION $SIZE, $LABEL $UUID $PRODNAME\n"
done

SELECTED=$(echo -e "$COMBINED_LIST" | yad --center --list --title="$titl"  --window-icon="ntpwgui.png" --image="ntpwgui.png" \
--text="Please choose the windows installation\nto modify user accounts:" \
--column="Windows Installation detected" \
--width=700 --height=400 \
--button="Cancel:1" --button="OK:0")

[ $? -ne 0 ] && rm -f /tmp/winversions && exit 1

echo $SELECTED
PARTITION=$(echo $SELECTED | cut -d'/' -f3 | cut -d' ' -f1)
echo $PARTITION

if grep -wq $PARTITION /proc/mounts; then
findmnt -no OPTIONS /dev/$PARTITION | grep -iw "ro" && yad --error --width=500 --height=200 --text="Operation not permitted. Failed to mount /dev/${PARTITION}.\n${MNTERR}" --title="$titl" --image="ntpwgui.png"  --window-icon="ntpwgui.png" && rm -f /tmp/winversions && exit 1
MOUNT_POINT=$(lsblk -n -r -o MOUNTPOINT /dev/$PARTITION)
else
if ntfs-3g.probe --readwrite /dev/$PARTITION; then
mount /dev/$PARTITION $TESTMOUNT
MOUNT_POINT=$(lsblk -n -r -o MOUNTPOINT /dev/$PARTITION)
else
PROBEOUT="$(ntfs-3g.probe --readwrite /dev/$PARTITION 2>&1)"
[ "$PROBEOUT" ] && yad --error --window-icon="ntpwgui.png" --image="ntpwgui.png" --width=500 --height=200 --text="Operation not permitted. Failed to mount /dev/${PARTITION}.\n${PROBEOUT}" --title="$titl" --button="Next:0" ||
yad --window-icon="ntpwgui.png" --image="ntpwgui.png" --width=500 --height=200 --text="${PROBERR}${PARTITION}." --title="$titl" --button="Next:0"
echo ${PROBEOUT}
if echo ${PROBEOUT} | grep -q "hibernat"; then
yad --width=400 --height=200 --title="$title" --image="ntpwgui.png"  --window-icon="ntpwgui.png" --text="Do you want to try to remove hibernation file ? \nPlease be aware that the hibernated session will be lost.\n" \
--button=Continuer:0 --button=Annuler:1
response=$?
if [ $response -eq 0 ]; then
echo "Trying to remove hiberfile"
if (! ntfs-3g.probe --readwrite /dev/$PARTITION); then
mount -t ntfs-3g -o remove_hiberfile /dev/$PARTITION $TESTMOUNT || {
ntfsfix /dev/$PARTITION
mount -t ntfs-3g -o remove_hiberfile /dev/$PARTITION $TESTMOUNT
sleep 1
umount /dev/$PARTITION
}
PROBEOUT="$(ntfs-3g.probe --readwrite /dev/$PARTITION 2>&1)"
if [ "$PROBEOUT" ]; then
yad --error --width=500 --height=200 --border=10 --text "${PROBERR}${PARTITION}.\n${PROBEOUT}\n\n" --image="ntpwgui.png"  --window-icon="ntpwgui.png" --title="$titl"
rm -f /tmp/winversions && exit 1
else
mount /dev/$PARTITION $TESTMOUNT
MOUNT_POINT=$(lsblk -nr -o MOUNTPOINT /dev/$PARTITION)
[ "$MOUNT_POINT" ] || {
sleep 1.25
MOUNT_POINT=$(lsblk -nr -o MOUNTPOINT /dev/$PARTITION)
}
fi
else
mount /dev/$PARTITION $TESTMOUNT && MOUNT_POINT=$(lsblk -nr -o MOUNTPOINT /dev/$PARTITION)
[ "$MOUNT_POINT" ] || {
sleep 1.25
MOUNT_POINT=$(lsblk -nr -o MOUNTPOINT /dev/$PARTITION)
}
fi
[ "$MOUNT_POINT" ] || { yad --error --width=500 --height=200 --border=10 --text "${PROBERR}${PARTITION},\nor encountered issue with volume ${PARTITION}." --image="ntpwgui.png"  --window-icon="ntpwgui.png" && rm -f /tmp/winversions && exit 1; }
else
echo "Canceled by user."
rm -f /tmp/winversions && exit 1
fi
else
rm -f /tmp/winversions && exit 1
fi
#
fi
fi

for FINDSAM in $WINPATH; do [ -e "$MOUNT_POINT/$FINDSAM" ] && SAMPATH="$MOUNT_POINT/$FINDSAM"; done

backupsam() {
backupfile="$(dirname "$SAMPATH")/SAM_backup$backupid"
if [ ! -f "$backupfile" ]; then
sudo \cp "$SAMPATH" "$backupfile"
fi
}

while true; do
data=$(sudo chntpw -l "$SAMPATH" | grep -E "^\| [0-9a-f]{4} \|")

if [ -z "$data" ]; then
yad --center --title=$titl --window-icon="ntpwgui.png" --image="ntpwgui.png" --text="\n  Error : no user found  \n" --button="OK:0"
rm -f /tmp/winversions
exit 1
fi

user_id=()
user_name=()
admin_status=()
lock_status=()

while IFS= read -r line; do
uid=$(echo "$line" | awk -F '|' '{print $2}' | xargs)
uname=$(echo "$line" | awk -F '|' '{print $3}' | xargs)
astatus=$(echo "$line" | awk -F '|' '{print $4}' | xargs)
lstatus=$(echo "$line" | awk -F '|' '{print $5}' | xargs)
[ -z "$astatus" ] && astatus="user"
[ -z "$lstatus" ] && lstatus="unlocked"
user_id+=("$uid")
user_name+=("$uname")
admin_status+=("$astatus")
lock_status+=("$lstatus")
done <<< "$data"

yad_data=""
length=${#user_id[@]}
for (( i=0; i<$length; i++ )); do
yad_data+="\"${user_id[$i]}\" \"${user_name[$i]}\" \"${admin_status[$i]}\" \"${lock_status[$i]}\" "
done

selected=$(eval yad --center --title "$titl" --window-icon="ntpwgui.png" --image="ntpwgui.png" --text "\"\n    Windows users on $PARTITION:\n\"" --list \
--column="UserID" --column="UserName" --column="AdminStatus" --column="LockStatus" \
$yad_data \
--height=500 --width=700 \
--button="Select:0" --button="Cancel:1")

if [ $? -eq 0 ]; then
selected_userid=$(echo "$selected" | awk -F '|' '{print $1}')
echo "Selected User ID: $selected_userid"
else
echo "No selection made or operation cancelled."
sudo umount $MOUNT_POINT
if [ $? -ne 0 ]; then
yad --center --error --title=$titl --window-icon="ntpwgui.png" --image="ntpwgui.png" --text="\n     Error unmounting partition.     \n"
rm -f /tmp/winversions
exit 1
fi
rm -f /tmp/winversions
exit 0
fi

selected_username=""
for (( i=0; i<$length; i++ )); do
if [ "${user_id[$i]}" == "$selected_userid" ]; then
selected_username="${user_name[$i]}"
break
fi
done

while true; do
action=$(yad --center --title=$titl --window-icon="ntpwgui.png" --image="ntpwgui.png" --list \
--text="\nSelect action for user $selected_username:\n" \
--radiolist \
--column="" --column="Action" \
TRUE "Clear password" FALSE "Promote to admin" FALSE "Unlock account" \
--height=400 --width=500 \
--button="OK:0" --button="Cancel:1")

if [ $? -eq 0 ]; then
selected_action=$(echo "$action" | awk -F '|' '{print $2}')
echo "Selected Action: $selected_action"

case $selected_action in
"Clear password")
backupsam
sudo chntpw -u "0x$selected_userid" "$SAMPATH"<< EOF
1
q
y
EOF
;;
"Promote to admin")
backupsam
sudo chntpw -u "0x$selected_userid" "$SAMPATH"<< EOF
3
y
q
y
EOF
;;
"Unlock account")
backupsam
sudo chntpw -u "0x$selected_userid" "$SAMPATH"<< EOF
2
q
y
EOF
;;
esac

yad --center --title=$titl --window-icon="ntpwgui.png" --image="ntpwgui.png" --text="\n   Action '$selected_action' was performed for user $selected_username   \n" --button="OK:0"
break
else
echo "No action selected or operation cancelled. Returning to user selection."
break
fi
done
done
