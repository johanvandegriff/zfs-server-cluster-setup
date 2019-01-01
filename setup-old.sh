#!/bin/bash
#https://github.com/zfsonlinux/pkg-zfs/wiki/HOWTO-install-EL7-(CentOS-RHEL)-to-a-Native-ZFS-Root-Filesystem
#1. Install CentOS to a hard drive or USB drive
#2. Run this on the installation
#3. Profit

#https://github.com/zfsonlinux/zfs/wiki/RHEL-and-CentOS

sudo yum install http://download.zfsonlinux.org/epel/zfs-release.el7_5.noarch.rpm
fingerprint=`gpg --quiet --with-fingerprint /etc/pki/rpm-gpg/RPM-GPG-KEY-zfsonlinux | grep "Key"`
if [[ "$fingerprint" != '      Key fingerprint = C93A FFFD 9F3F 7B03 C310  CEB6 A9D5 A1C0 F14A B620' ]]; then
	>&2 echo "Incorrect fingerprint! '$fingerprint'"
	exit 1
fi

file="/etc/yum.repos.d/zfs.repo"
tmpfile=$(mktemp)
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


sudo yum install zfs-dracut

#may need to reboot here

modprobe zfs
if dmesg | egrep "SPL|ZFS"; then
	echo "SUCCESS: zfs is installed"
else
	echo "FAILURE: zfs failed to install!"
	exit 1
fi

echo "What do you want to name the pool?"
read poolname
if ( echo "$poolname" | grep -q ' ' ) || [[ -z "$poolname" ]]; then
	>&2 echo "FAILURE: pool name contains spaces or is empty: \"$poolname\""
	exit 1
fi

lsblk
disks=`ls /dev/disk/by-id/ -l | awk '{print $9, $10, $11}' | sed 's,../../,,' | grep -v [0-9]$ | grep -v '^  $'`
echo "$disks"
echo "Enter which disk(s) you want to usem separated by spaces. e.g. \"sdb sdc\""
read selected
ids=
for d in $selected
do
	id=`echo "$disks" | grep "${d}$" | head -1 | awk '{print $1}'`
	if [[ -z "$id" ]]; then
		>&2 echo "FAILURE: no /dev/disk/by-id found for drive \"$d\"!"
		exit 1
	fi
	ids="$ids /dev/disk/by-id/$id"
done

command="zpool create -d -o feature@async_destroy=enabled -o feature@empty_bpobj=enabled -o feature@lz4_compress=enabled -o ashift=12 -O compression=lz4 -O atime=off $poolname $ids"
#        zpool create -d -o feature@async_destroy=enabled -o feature@empty_bpobj=enabled -o feature@lz4_compress=enabled -o ashift=12 -O compression=lz4 rpool /dev/sda3
#        zpool create -d -o feature@async_destroy=enabled -o feature@empty_bpobj=enabled -o feature@lz4_compress=enabled -o ashift=12 -O compression=lz4 -O copies=2 -O acltype=posixacl -O xattr=sa -O utf8only=on -O atime=off -O relatime=on rpool 
echo "$command"
echo "Is this OK? (yes/no)"
read answer
if [[ "$answer" != "yes" ]]; then
	>&2 echo "ABORTED: did not answer \"yes\""
	exit 1
fi

$command
zpool status -v "$poolname"
udevadm trigger
