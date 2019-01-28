#!/bin/bash

########################################################################
#
# This script follows a guide to install Ubuntu on the ZFS filesystem:
# https://github.com/zfsonlinux/pkg-zfs/wiki/HOWTO-install-Ubuntu-18.04-to-a-Whole-Disk-Native-ZFS-Root-Filesystem-using-Ubiquity-GUI-installer
#
########################################################################

. `dirname "$0"`/install-common.sh || exit 1


if [[ "$1" == "--cleanup" ]]; then
    poolname2=`zpool list | tail -n +2 | cut -d' ' -f1`
    numpools=`echo $poolname2 | wc -l`
    if [[ $numpools != 1 ]]; then
        error "$numpools zfs pools found; expected 1"
    fi
    zfs snapshot $poolname2/ROOT/ubuntu-1@post-reboot || error "Error making snapshot of zfs pool"
    zfs destroy $poolname2/ubuntu-temp || error "Error removing temporary"
    apt update || error "Error with apt update"
    apt dist-upgrade -y || error "Error with dist-upgrade"
    zfs snapshot $poolname2/ROOT/ubuntu-1@post-reboot-updates || error "Error making post-update snapshot"
    color green "Cleanup succeeded! Enjoy your new Ubuntu installation on ZFS :)"
    exit
fi

apt update || error "Error retrieving latest package lists (apt update)"
apt install -y zfsutils || error "Error installing zfsutils package"

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


#this command creates a mirror of the 2 disks with certain properties and optimizations enabled
command="sudo zpool create -d -o feature@async_destroy=enabled -o feature@empty_bpobj=enabled -o feature@lz4_compress=enabled -o ashift=12 -O compression=lz4 -O atime=off $poolname mirror -f $ids" #$ids_part1"

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
	error "FAILURE: zfs pool creation failed! This may have been caused by an already exsisting pool. Unmount it with \"sudo umount -R /$poolname2/; sudo zpool export $poolname2\" and re-run the script to continue."
fi

#upgrade and view the status of the pool
sudo zpool upgrade "$poolname" || error "Error upgrading $poolname"
sudo zpool status -v "$poolname" || error "Error getting status for $poolname"
sudo udevadm trigger || error "Error updating the udev rule"


#zpool create -f -o ashift=12 -O atime=off -O compression=lz4 -O normalization=formD -O recordsize=1M -O xattr=sa $poolname /dev/disk/by-id/ata-ST9999999999_10000000


zfs create -V 10G $poolname/ubuntu-temp || error "Error creating temporary dataset in $poolname"


cat << EOF
1. Choose any options you wish until you get to the 'Installation Type' screen. (For server applications, you may want to select the minimal installation)
2. Select 'Erase disk and install Ubuntu' and click 'Continue'.
3. Change the 'Select drive:' dropdown to '/dev/zd0 - 10.7 GB Unknown' and click 'Install Now'.
4. A popup summarizes your choices and asks 'Write the changes to disks?". Click 'Continue'.
5. At this point continue through the installer normally.
6. Finally, a message comes up 'Installation Complete'. Click the 'Continue Testing'.
EOF

ubiquity --no-bootloader || error "Error with graphical installer"

echo "Press ENTER to continue"
read a

zfs create $poolname/ROOT || error "Error creating ROOT dataset in $poolname"
zfs create $poolname/ROOT/ubuntu-1 || error "Error creating ROOT/ubuntu-1 dataset in $poolname"
rsync -avPX /target/. /$poolname/ROOT/ubuntu-1/. || error "Error copying files to new dataset"


for d in proc sys dev
do
    mount --bind /$d /$poolname/ROOT/ubuntu-1/$d || error "Error mounting $d to the zfs filesystem for chroot"
done

mych="chroot /$poolname/ROOT/ubuntu-1"

cp /etc/resolv.conf /$poolname/ROOT/ubuntu-1/etc/resolv.conf 
#$mych echo "nameserver 8.8.8.8" | tee -a /etc/resolv.conf
$mych apt update || error "Error retrieving package lists (in chroot)"
$mych apt install -y zfs-initramfs || error "Error installing zfs-initramfs (in chroot)"

#comment everything out in /etc/fstab
fstab_file="/$poolname/ROOT/ubuntu-1/etc/fstab"
fstab_contents=`cat $fstab_file`
echo "$fstab_contents" | awk '{print "#" $0}' | sudo tee "$fstab_file" || error "Error updating \"$fstab_file\""

#$mych nano /etc/fstab         ## comment out the lines for the mountpoint "/" and "/swapfile" and exit

$mych rm /swapfile || error "Error removing swapfile (in chroot)"

$mych update-grub || error "Error updating grub (in chroot)"

for disk in $ids
do
    $mych sgdisk -a1 -n2:512:2047 -t2:EF02 $disk || error "Error formatting $disk"
    $mych grub-install $disk || error "Error installing grub to $disk"
done

umount -R /$poolname/ROOT/ubuntu-1 || error "Error unmounting dataset"
zfs set mountpoint=/ $poolname/ROOT/ubuntu-1 || error "Error setting mountpoint"
zfs snapshot $poolname/ROOT/ubuntu-1@pre-reboot || error "Error making zfs snapshot"
swapoff -a || error "Error unmounting swapfile"
umount /target    || error "Error unmounting /target"
zpool export $poolname   || error "Error exporting zfs pool"
#shutdown -r 0 || error "Error shutting down"

echo "reboot now to finish installation"

