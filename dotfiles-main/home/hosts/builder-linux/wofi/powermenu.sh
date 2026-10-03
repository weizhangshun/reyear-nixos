#!/bin/bash
op=$(echo -e "Logout\nReboot\nShutdown" | wofi -dmenu -p "Power Menu")

if [[ $op == "Logout" ]]; then
    hyprctl dispatch exit
elif [[ $op == "Reboot" ]]; then
    systemctl reboot
elif [[ $op == "Shutdown" ]]; then
    systemctl poweroff
fi

