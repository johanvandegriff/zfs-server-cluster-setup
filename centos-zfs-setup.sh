#!/bin/bash

########################################################################
#
# This script follows a guide to install CentOS on the ZFS filesystem:
# https://github.com/zfsonlinux/pkg-zfs/wiki/HOWTO-install-EL7-(CentOS-RHEL)-to-a-Native-ZFS-Root-Filesystem
#
# Throughout the script, there are section numberings that match up to
# the sections in the document (as of Jan 1, 2019)
#
# IMPORTANT: The first step (1.1) is not covered in this script, so it
# must be done by the user:
#
# "1.1 Install EL7 on a separate hard disk/USB disk that will NOT be
# part of the ZFS pool. EL7 installation process is not covered here,
# and should be pretty straight forward."
#
# #section1.1
# My recommended steps for completing item 1.1 are as follows:
#   1.1.1 Acquire 2 thumb drives (at least 2GB and at least 8GB).
#   1.1.2 Download the latest CentOS iso:
#         https://www.centos.org/download/
#   1.1.3 Flash the ISO to the smaller thumb drive with etcher:
#         https://www.balena.io/etcher/
#   1.1.4 Boot from the thumb drive with the iso.
#   1.1.5 Plug in the other thumb drive.
#   1.1.6 Start the install Centos install process, selecting the 2nd 
#         thumb drive as the target device for installation.
#
# This script takes care of updating the CentOS packages (yum update)
#
########################################################################

. `dirname "$0"`/install-common.sh || exit 1

warning "This script did not work on CentOS 7.6 (grub2-install: error: unknown filesystem.) and we have moved over to Ubuntu 18.04 using the other script, which works great."
#TODO automatically check if the system is installed or live
#ask if the user has installed the system
yes_or_no "Are you running this script from an installation of CentOS? (NOT a live USB!!)"
if [[ "$answer" == n ]]; then
  error "Not running from CentOS installation! See the comment at the beginning of this script for more info."
fi

#section 1.1 (2nd part; 1st part has to be dome manually -- see note at beginning of script)
sudo yum check-update
sudo yum update -y || error "yum update failed!"


#section 1.2
#https://github.com/zfsonlinux/zfs/wiki/RHEL-and-CentOS

#determine the version of CentOS and put in the format "7_5" or "7_6" to be used in the url on the following line
centos_version=`cat /etc/centos-release | cut -f4 -d" " | cut -f1-2 -d. | tr . _`

#install zfs-release from the zfsonlinux project
sudo yum install -y http://download.zfsonlinux.org/epel/zfs-release.el${centos_version}.noarch.rpm

#check the fingerprint and abort if it doesn't match
fingerprint=`gpg --quiet --with-fingerprint /etc/pki/rpm-gpg/RPM-GPG-KEY-zfsonlinux | grep "Key"`
if [[ "$fingerprint" != '      Key fingerprint = C93A FFFD 9F3F 7B03 C310  CEB6 A9D5 A1C0 F14A B620' ]]; then
	error "Incorrect fingerprint! '$fingerprint'"
fi

#edit the zfs.repo file, disabling the main [zfs] section and enabling the [zfs-kmod] section
file="/etc/yum.repos.d/zfs.repo"
tmpfile=$(mktemp) #use a tempfile to hold the changes
i=0
type=
while read a; do
	if [[ "$a" == "[zfs]" ]] || [[ "$a" == "[zfs-kmod]" ]]; then
		type="$a"
	fi
	if [[ -z "$type" ]]; then
		i=0
		echo "$a"
	else
		i=$((i+1))
		if [[ "$i" == "4" ]]; then
			if [[ "$type" == "[zfs]" ]]; then
				echo "${a//enabled=1/enabled=0}"
			else
				echo "${a//enabled=0/enabled=1}"
			fi
			type=
		else
			echo "$a"
		fi
	fi
done < "$file" > "$tmpfile"
sudo mv "$tmpfile" "$file"

#install zfs-dracut
sudo yum install -y zfs-dracut || error "zfs-dracut failed to install!"

#may need to reboot here??
#note: has been tested multiple times and there is no need to reboot

#section 1.3
#load the zfs kernel module
#this step failed after upgrating CentOS, and the resolution was found at the link in the following error message
sudo modprobe zfs || error "Failed to load zfs kernel module! See: https://github.com/zfsonlinux/zfs/issues/1347"

#check if the module was loaded
if dmesg | egrep -i "SPL|ZFS" > /dev/null; then
	color green "SUCCESS: zfs is installed."
else
	error "FAILURE: zfs failed to install! (no output in dmesg relating to zfs)"
fi

#section 2.1
#note: this script does not follow any of the subsections in the document
#because there we no sections on how to set up a mirrored pool.
#However, the script is labelled with the sections for the raidz2
#as it was the most similar.

#ask for the name of the pool and check to make sure it is valid
echo "What do you want to name the pool?"
read poolname
if ( echo "$poolname" | grep -q ' ' ) || [[ -z "$poolname" ]]; then
	error "FAILURE: pool name contains spaces or is empty: \"$poolname\". The convention is lowercase letters only, no spaces."
fi

#show user a choice of disk and get disk info; see function defined above
disk_status
echo "$disks"
echo "Enter which disk(s) you want to use separated by spaces. e.g. \"sdb sdc\""
color orange "WARNING: at this time, the only supported array type is a mirror with 2 disks. The script needs to be modified for different configurations. (You can add additional mirrors later.) Please enter 2 disks."
read selected

#TODO add support for configs other than mirror of just 2 disks
#make sure only 2 disks were selected
num_selected=`echo "$selected" | wc -w`
if [[ "$num_selected" -ne 2 ]]; then
    error "Only mirrors of exactly 2 disks are supported, but you entered $num_selected disks."
fi

#loop through the disks the user selected and find them by id
ids=
ids_part1=
for d in $selected; do
	id=`echo "$disks" | grep "${d}$" | head -1 | awk '{print $1}'`
	if [[ -z "$id" ]]; then
		error "FAILURE: no /dev/disk/by-id found for drive \"$d\"!"
	fi
	ids="$ids /dev/disk/by-id/$id"
	ids_part1="$ids_part1 /dev/disk/by-id/${id}-part1"
done

#TODO uefi is currently disabled until some of the later commands are updated
#yes_or_no "Do you want UEFI? Legacy BIOS will be used otherwise."
#uefi="$answer"
uefi=n

#confirm the disks to be formatted
yes_or_no "Format disks and create partitions? $ids (CANNOT BE UNDONE!)"
if [[ "$answer" != "y" ]]; then
	error "ABORTED: user cancelled disk formatting."
fi

#section 2.1.2.1
#format and partition the disks
for id in $ids; do
	echo -n "Formatting $id ..."
	sudo sgdisk --zap-all "$id" || error "error formatting disk: \"$id\""
    #the first partition will be the uefi/legacy boot partition
	if [[ "$uefi" == "n" ]]; then
		sudo sgdisk -a1 -n2:34:2047  -t2:EF02 "$id" || error "error creating boot partition for disk: \"$id\""
	else
		sudo sgdisk     -n3:1M:+512M -t3:EF00 "$id" || error "error creating uefi boot partition for disk: \"$id\""
	fi
    #the second will be managed by zfs
	sudo sgdisk         -n1:0:0      -t1:BF01 "$id" || error "error creating zfs partition for disk: \"$id\""
	echo "Done."
done

#section 2.1.2.2
#this command creates a mirror of the 2 disks with certain properties and optimizations enabled
command="sudo zpool create -d -o feature@async_destroy=enabled -o feature@empty_bpobj=enabled -o feature@lz4_compress=enabled -o ashift=12 -O compression=lz4 -O atime=off $poolname mirror -f $ids_part1"
#        sudo zpool create -d -o feature@async_destroy=enabled -o feature@empty_bpobj=enabled -o feature@lz4_compress=enabled -o ashift=12 -O compression=lz4 rpool /dev/sda3
#        sudo zpool create -d -o feature@async_destroy=enabled -o feature@empty_bpobj=enabled -o feature@lz4_compress=enabled -o ashift=12 -O compression=lz4 -O copies=2 -O acltype=posixacl -O xattr=sa -O utf8only=on -O atime=off -O relatime=on rpool 

#confirm the command with the user
disk_status
color orange "$command"
yes_or_no "Is this OK?"
if [[ "$answer" != "y" ]]; then
	error "ABORTED: user cancelled zfs pool creation"
fi

#run the command to create the zpool
if $command; then
	color green "SUCCESS: zfs pool creation succeeded!"
else
    #retrieve the name of the offending pool(s)
    poolname2=`zpool list | tail -n +2 | cut -d' ' -f1`
	error "FAILURE: zfs pool creation failed! This may have been caused by an already exsisting pool. Unmount it with \"sudo umount -R /$poolname2/ROOT; sudo zpool export $poolname2\" and re-run the script to continue."
fi

#upgrade and view the status of the pool
sudo zpool upgrade "$poolname" || error "Error upgrading $poolname"
sudo zpool status -v "$poolname" || error "Error getting status for $poolname"
sudo udevadm trigger || error "Error updating the udev rule"

#section 2.2
#create a dataset called ROOT
sudo zfs create "$poolname/ROOT" || error "Error creating ROOT dataset in $poolname"

#mount the current filesystem to /mnt/tmp
sudo mkdir -p /mnt/tmp || error 'Error creating directory "/mnt/tmp"'
sudo mount --bind / /mnt/tmp || error 'Error mounting "/" to "/mnt/tmp"'

#copy the current filesystem into the ROOT dataset
sudo rsync -avPX /mnt/tmp/. "/$poolname/ROOT/." || error "Error copying root filesystem into ROOT dataset on $poolname"
sudo umount /mnt/tmp || error 'Error unmounting "/mnt/tmp"'

#section 2.3
#comment everything out in /etc/fstab
fstab=`cat "/$poolname/ROOT/etc/fstab"`
echo "$fstab" | awk '{print "#" $0}' | sudo tee "/$poolname/ROOT/etc/fstab" || error 'Error updating "/etc/fstab"'

#section 2.3 (there are 2 of the same section number in the document...)
grubfile="/$poolname/ROOT/etc/default/grub"

# cat "$grubfile"
#GRUB_TIMEOUT=5
#GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
#GRUB_DEFAULT=saved
#GRUB_DISABLE_SUBMENU=true
#GRUB_TERMINAL_OUTPUT="console"
#GRUB_CMDLINE_LINUX="rd.lvm.lv=cl00/root rd.lvm.lv=cl00/swap rhgb quiet"
#GRUB_DISABLE_RECOVERY="true"

#edit the grub config with sed
sudo sed -i -e 's,rhgb quiet"$,rhgb quiet boot=zfs root=ZFS='"$poolname"'/ROOT",g' "$grubfile" || error "Error editing \"$grubfile\" (1)"
sudo sed -i -e 's,GRUB_HIDDEN_TIMEOUT=0,#GRUB_HIDDEN_TIMEOUT=0,g' "$grubfile" || error "Error editing \"$grubfile\" (2)"
to_add='GRUB_PRELOAD_MODULES="part_gpt zfs"'
if ! grep -q "$to_add" "$grubfile"; then
	echo "$to_add" | sudo tee -a "$grubfile" || error "Error editing \"$grubfile\" (3)"
fi

# cat "$grubfile"
#GRUB_TIMEOUT=5
#GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
#GRUB_DEFAULT=saved
#GRUB_DISABLE_SUBMENU=true
#GRUB_TERMINAL_OUTPUT="console"
#GRUB_CMDLINE_LINUX="rd.lvm.lv=cl00/root rd.lvm.lv=cl00/swap rhgb quiet boot=zfs root=ZFS=slice/ROOT"
#GRUB_DISABLE_RECOVERY="true"
#GRUB_PRELOAD_MODULES="part_gpt zfs"

#section 2.4
#mount the important dirs to the chroot location
for dir in proc sys dev; do
	sudo mount --bind "/$dir" "/$poolname/ROOT/$dir" || error "Error mounting \"/$dir\" to \"$poolname\""
done

#establish a quick way of running commands through chroot in the ROOT dataset
mych="sudo chroot /$poolname/ROOT/"

#create /boot/grub2 since it didn't exist and was causing an error with the next line
$mych mkdir -p /boot/grub2 || error "Error creating /boot/grub2 on $poolname"

#link the devices from /dev/disk/by-id to just /dev to allow grub to find them
$mych ln -s /dev/disk/by-id/* /dev/ -i || error "Error linking disks from /dev/disk/by-id to /dev"

#$mych export ZPOOL_VDEV_NAME_PATH=YES

#generate the grub config
$mych grub2-mkconfig -o /boot/grub2/grub.cfg || error "Error generating grub config"

#check to see if the ROOT dataset appears in grub.cfg. Currently, it doesn't and this needs to be investigated
$mych grep ROOT /boot/grub2/grub.cfg || warning "FIXME: grub install not verified; could mean the system won't boot!"
###!!!should return a few lines but doesn't

#section 2.5 is optional, so yallready know we're skipping that

#section 2.6.2 (again, this is for raidz2 but it works for mirroring too)
#install grub to each of the disks in the array, being careful to use /dev/<device> to avoid a bug/error
ids_dev=`echo "$ids" | sed "s,/disk/by-id,,g"`
for disk in $ids_dev
do
    $mych grub2-install --boot-directory=/boot $disk || warning "FIXME: Error installing grub to disk \"$disk\""
done

#!!!!! current error:
#Installing for i386-pc platform.
#grub2-install: error: unknown filesystem.

#section 2.6.3
#no need to do this for later versions of centos:
#$mych echo 'add_dracutmodules+="zfs"' >> /etc/dracut.conf

#install the kernel image to dracut
$mych dracut -f -v /boot/initramfs-$(uname -r).img $(uname -r) || error "Error adding kernel image to dracut!"

#TODO fix the bug where the default boot item is not updated by dracut

#unmount the important dirs
for dir in proc sys dev; do
	sudo umount "/$poolname/ROOT/$dir" || error "error unmounting /$dir from $poolname"
done

#section 2.7
$mych rm /etc/zfs/zpool.cache -f || error "Error removing zpool.cache!"

#section 2.8
yes_or_no "Do you want to reboot now to complete the installation? Be sure to select one of the devices with zfs to boot from when starting back up."
if [[ "$answer" == y ]]; then
    sudo reboot
fi
