#!/bin/bash
export NO_AT_BRIDGE=1;default_title="My Files Server";default_port=8000;default_shared_folder="/home/$USER/"
while true; do result=$(yad --title="gohttpserver Configuration" --window-icon=network-server --form --width=520 --height=350 \
--text="\n<span foreground='#0000FF'><b><u>Configure your gohttpserver settings below:</u></b></span>\n\n  - <i>Shared folder</i>: Directory to be served\n  - <i>Server title</i>: Title displayed on the web interface\n  - <i>Port</i>: Port number for the server\n  - <i>Username and Password</i>: Optional. (Leave both empty for no authentication)\n  - <i>Upload/Delete</i>: Enable file upload and delete support\n\n" \
--field="<span foreground='#000080'><b>Shared folder </b></span>":DIR "$default_shared_folder" \
--field="<span foreground='#800080'><b>Server title </b></span>" "$default_title" \
--field="<span foreground='#804552'><b>Port </b></span>":NUM "$default_port" \
--field="<span foreground='#454545'><b>Username </b></span>" "" --field="<span foreground='#FF0000'><b>Password </b></span>":H "" \
--field="Enable Upload":CHK FALSE --field="Enable Delete ( !! Warning !! )":CHK FALSE --button="Cancel:1" --button="Start Server:0")
if [[ $? -eq 1 ]]; then echo "Configuration cancelled.";exit 0;fi
IFS='|' read -r shared_folder server_title server_port server_user server_pass enable_upload enable_delete <<< "$result"
if [[ -z "$enable_delete" ]]; then  echo "Configuration cancelled.";exit 0;fi
if [[ -z "$shared_folder" ]]; then yad   --title="gohttpserver Configuration" --window-icon=network-server --width=450 --height=150 --error --text="Shared folder must be specified.";continue;fi
if [[ -n "$server_user" && -z "$server_pass" ]] || [[ -z "$server_user" && -n "$server_pass" ]]; then
yad  --title="gohttpserver Configuration" --window-icon=network-server  --error --text="Both username and password must be filled if authentication is required.";continue;fi;break;done
cmd="gohttpserver --theme=black -r \"$shared_folder\" --title \"$server_title\" --port \"$server_port\""
if [[ -n "$server_user" && -n "$server_pass" ]]; then cmd+=" --auth-type http --auth-http \"$server_user:$server_pass\"";fi
msg="";if [[ "$enable_upload" == "TRUE" ]]; then cmd+=" --upload";msg=$msg"-- upload enabled -- ";fi
if [[ "$enable_delete" == "TRUE" ]]; then cmd+=" --delete";msg=$msg"-- delete enabled -- ";fi
ipserv=$(ip -o -4 a | awk '!/127.0.0.1/ {print $4}' | cut -d/ -f1 | head -n 1)
if [ -z "$ipserv" ]; then goip="local url: http://127.0.0.1:$server_port/";else goip="url: http://$ipserv:$server_port/";fi
terminal_title="gohttpserver - $server_title -- Shared folder: $shared_folder -- $goip"
konsole -T "$terminal_title" --caption "" --geometry 950x500 --icon network-server -e bash -c "echo;printf '\033[31;1;4m=== Close this windows to quit gohttpserver ===\033[0m';echo;echo;echo 'Server $goip';echo $msg;echo;$cmd;echo;echo 'Press Enter to close this window'; read"
