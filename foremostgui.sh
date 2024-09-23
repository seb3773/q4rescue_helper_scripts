#!/bin/bash
export NO_AT_BRIDGE=1
fico="/usr/share/icons/hicolor/128x128/apps/foremostgui.png"
function _foremost() {
d=$( date '+%F_%H-%M-%S' )
default_outdir="$PWD/foremost_out_$d"
echo $default_outdir
parts=$(df -Th | grep -e "^/dev/*" | awk '{print $1}' | tr "\n" "!" | sed 's/!$//')
parts="None!$parts"
result=$(yad --form \
--title="ForemostGUI" \
--window-icon="$fico" \
--field="\n:LBL" "" \
--text="<b> ++ Configure data recovery ++</b>" \
--width=800 \
--field="Select a partition :CB" "$parts" \
--field="OR select disk image :FL" "" \
--field="<i>> You can select either a partition or a disk image (not both)</i>\n\n:LBL" "" \
--field="Extensions :" "" \
--field="<i>> Use 'all' for all known extensions or enter an extension, multiple extensions can be entered separated with commas (for example: jpg,bmp,png )</i>\n\n:LBL" "" \
--field="Output folder :CDIR" "$default_outdir" \
--field="Enable quick mode :CHK" "FALSE" \
--field="Only write the audit file, don't recover files :CHK" "FALSE" \
--separator="|")
if [ $? -ne 0 ]; then exit;fi
IFS='|' read -ra fields <<< "$result"
addr=$(echo "${fields[1]}" | sed 's/^ *//; s/ *$//')
imgfile=$(echo "${fields[2]}" | sed 's/^ *//; s/ *$//')
ext=$(echo "${fields[4]}" | sed 's/^ *//; s/ *$//')
outdir=$(echo "${fields[6]}" | sed 's/^ *//; s/ *$//')
quick_mode=${fields[7]}
audit_only=${fields[8]}
[ "$addr" = "None" ] && addr=""
[ -z "$imgfile" ] && imgfile="None"
[ -z "$ext" ] && ext="all"
if [ -n "$addr" ] && [ "$imgfile" != "None" ]; then
yad --window-icon="$fico" --title="ForemostGUI" --error --text="Error: You cannot select both a partition and a disk image file."
return;fi
if [ -z "$addr" ] && [ "$imgfile" = "None" ]; then
yad --window-icon="$fico" --title="ForemostGUI" --error --text="Error: You must select either a partition or a disk image file."
return;fi
outdir=$(realpath "$outdir")
tdesudo -c ls /dev/null -d -i password --comment "Running Foremost requires root privileges"
oksu=$(sudo -n echo 1 2>&1 | grep 1)
if [[ ! $oksu -eq 1 ]]; then
yad --window-icon="$fico" --title="ForemostGUI" --error --text="Error granting root privileges."
return;fi
if [ ! -d "$outdir" ]; then sudo mkdir -p "$outdir";fi
opr="Recovery";foremost_cmd="sudo foremost -Q"
[ "$quick_mode" = "TRUE" ] && foremost_cmd+=" -q"
[ "$audit_only" = "TRUE" ] && foremost_cmd+=" -w" && opr="Audit"
foremost_cmd+=" -t $ext -o $outdir"
if [ -n "$addr" ]; then $foremost_cmd -i "$addr" >/dev/null 2>&1 &
else $foremost_cmd -i "$imgfile" >/dev/null 2>&1 &
fi;foremost_pid=$!;start_time=$(date +%s)
(
while kill -0 $foremost_pid 2>/dev/null; do
current_time=$(date +%s)
elapsed=$((current_time - start_time))
elapsed_formatted=$(printf "%02d:%02d:%02d" $((elapsed/3600)) $((elapsed%3600/60)) $((elapsed%60)))
file_count=0
file_count=$(find "$outdir" -type f ! -name "audit.txt" | wc -l)
if [ "$audit_only" = "TRUE" ]; then
 echo "#$opr in progress...\nTime elapsed: $elapsed_formatted"
else
echo "#$opr in progress...\nTime elapsed: $elapsed_formatted\nFiles recovered: $file_count"
fi
echo "0"
sleep 2
done
echo "100"
echo "# $opr completed"
) | yad --window-icon="$fico" --progress --pulsate --auto-close --text="$opr in progress..." --title="ForemostGUI" --width=600 --height=150 --button="Cancel:1"
progress_exit=$?
if [ $progress_exit -eq 1 ]; then
tdesudo -c ls /dev/null -d -i password --comment "Closing running Foremost session requires root privileges"
echo "killing process"
sudo kill $foremost_pid
wait $foremost_pid 2>/dev/null
sudo konqueror --profile filemanagement "$outdir" &
yad --window-icon="$fico" --info  --width=300 --height=100 --title="ForemostGUI" --text="$opr process canceled."
else
sudo konqueror --profile filemanagement "$outdir" &
yad --window-icon="$fico" --question --title="ForemostGUI" --text="$opr completed.\nOutput folder:\n\"$outdir\"\n\nDo you want to start another session?"
if [ $? -eq 0 ]; then
_foremost
fi;fi
}
_foremost