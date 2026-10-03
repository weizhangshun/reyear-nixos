#!/bin/bash
# Kill portals and background services that cause GDM to hang
systemctl --user stop xdg-desktop-portal-hyprland
systemctl --user stop xdg-desktop-portal
sleep 1
# Finally, exit Hyprland
hyprctl dispatch exit

