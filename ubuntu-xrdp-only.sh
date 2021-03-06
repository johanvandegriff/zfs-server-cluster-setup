#!/bin/bash

#https://medium.com/@vivekteega/how-to-setup-an-xrdp-server-on-ubuntu-18-04-89f7e205bd4e
#https://community.spiceworks.com/how_to/155718-install-xrdp-on-ubuntu-18-04

. `dirname "$0"`/install-common.sh || exit 1

apt update || error "Error with apt update"
apt install -y xrdp xfce4 xfce4-whiskermenu-plugin xfwm4-themes || error "Error installing xrdp and xfce"

echo xfce4-session > /home/$SUDO_USER/.xsession || error "Error editing .xsession"

# allow just RDP through the local firewall
ufw allow 3389/tcp || error "Error allowing port 3389 for xrdp"
# restart xrdp 
/etc/init.d/xrdp restart || error "Error restarting xrdp"

apt install -y tmux xclip htop glances openssh-server git || error "Error installing packages"

ufw allow 22/tcp || error "Error allowing firewall port 22 for ssh"

echo y | ufw enable || error "Error enabling the firewall"

color green "Importing xfce (and other) settings..."
for file in $(ls -A `dirname "$0"`/desktop-settings)
do
  path=`dirname "$0"`/desktop-settings/"$file"
  cp -var "$path" ~ || error "Error copying $file"
  chown -R $SUDO_USER:$SUDO_USER "$path"
done

color green "reboot to finish the installation"
