#!/bin/bash

#TODO add section numberings from document
#TODO add explanation at the beginning
#TODO add comments throughout

#https://github.com/zfsonlinux/pkg-zfs/wiki/HOWTO-install-EL7-(CentOS-RHEL)-to-a-Native-ZFS-Root-Filesystem
#1. Install CentOS to a hard drive or USB drive
#2. Run this on the installation
#3. Profit


#UTILITIES
#function for terminal colors that supports color names and nested colors
color() {
    color="$1"
    shift
    text="$@"
    case "$color" in
        # text attributes
#        end) num=0;;
        bold) num=1;;
        special) num=2;;
        italic) num=3;;
        underline|uline) num=4;;
        reverse|rev|reversed) num=7;;
        concealed) num=8;;
        strike|strikethrough) num=9;;
        # foreground colors
        black) num=30;;
        D_red) num=31;;
        D_green) num=32;;
        D_yellow) num=33;;
        D_orange) num=33;;
        D_blue) num=34;;
        D_magenta) num=35;;
        D_cyan) num=36;;
        gray) num=37;;
        D_gray) num=30;;
        red) num=31;;
        green) num=32;;
        yellow) num=33;;
        orange) num=33;;
        blue) num=34;;
        magenta) num=35;;
        cyan) num=36;;
        # background colors
        B_black) num=40;;
        BD_red) num=41;;
        BD_green) num=42;;
        BD_yellow) num=43;;
        BD_orange) num=43;;
        BD_blue) num=44;;
        BD_magenta) num=45;;
        BD_cyan) num=46;;
        BL_gray) num=47;;
        B_gray) num=5;;
        B_red) num=41;;
        B_green) num=42;;
        B_yellow) num=43;;
        B_orange) num=43;;
        B_blue) num=44;;
        B_magenta) num=45;;
        B_cyan) num=46;;
        B_white) num=47;;
#        +([0-9])) num="$color";;
#        [0-9]+) num="$color";;
        *) num="$color";;
#        *) echo "$text"
#             return;;
    esac


    mycode='\033['"$num"'m'
    text=$(echo "$text" | sed -e 's,\[0m,\[0m\\033\['"$num"'m,g')
    echo -e "$mycode$text\033[0m"
}

#display a message to stderr in bold red and exit with error status
error(){
    #bold red
    color bold `color red "$@"` 1>&2
    exit 1
}

#display a message to stderr in bold yellow
warning(){
    #bold yellow
    color bold `color yellow "$@"` 1>&2
}

#a yes or no prompt
yes_or_no(){
    prompt="$@ [y/n]"
    answer=
    while [[ -z "$answer" ]]; do #repeat until a valid answer is given
        read -p "$prompt" -n 1 response #read 1 char
        case "$response" in
            y|Y)answer=y;;
            n|N)answer=n;;
            *)color yellow "
Enter y or n.";;
        esac
    done
    echo
}




disk_status() {
	lsblk
	disks=`ls /dev/disk/by-id/ -l | awk '{print $9, $10, $11}' | sed 's,../../,,' | grep -v [0-9]$ | grep -v '^  $'`
}








#https://github.com/zfsonlinux/zfs/wiki/RHEL-and-CentOS

centos_version=`cat /etc/centos-release | cut -f4 -d" " | cut -f1-2 -d. | tr . _`
#centos_version will end up in the format "7_5" or "7_6"
sudo yum install -y http://download.zfsonlinux.org/epel/zfs-release.el${centos_version}.noarch.rpm
fingerprint=`gpg --quiet --with-fingerprint /etc/pki/rpm-gpg/RPM-GPG-KEY-zfsonlinux | grep "Key"`
if [[ "$fingerprint" != '      Key fingerprint = C93A FFFD 9F3F 7B03 C310  CEB6 A9D5 A1C0 F14A B620' ]]; then
	error "Incorrect fingerprint! '$fingerprint'"
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


sudo yum install -y zfs-dracut

#may need to reboot here

modprobe zfs || error "Failed to load zfs kernel module! See: https://github.com/zfsonlinux/zfs/issues/1347"
if dmesg | egrep -i "SPL|ZFS" > /dev/null; then
	color green "SUCCESS: zfs is installed."
else
	error "FAILURE: zfs failed to install!"
fi

echo "What do you want to name the pool?"
read poolname
if ( echo "$poolname" | grep -q ' ' ) || [[ -z "$poolname" ]]; then
	error "FAILURE: pool name contains spaces or is empty: \"$poolname\""
fi

disk_status

echo "$disks"
echo "Enter which disk(s) you want to use separated by spaces. e.g. \"sdb sdc\""
color orange "WARNING: at this time, the only supported array type is a mirror with 2 disks. The script needs to be modified for different configurations. (You can add additional mirrors later.) Please enter 2 disks."
read selected

#TODO add support for configs other than mirror of just 2 disks
num_selected=`echo "$selected" | wc -w`
if [[ "$num_selected" -ne 2 ]]; then
    error "Only mirrors of exactly 2 disks are supported, but you entered $num_selected disks."
fi

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

yes_or_no "Do you want UEFI? Legacy BIOS will be used otherwise."
uefi="$answer"

yes_or_no "Format disks and create partitions? $ids"
if [[ "$answer" != "y" ]]; then
	error "ABORTED: formatting disks cancelled."
fi

for id in $ids; do
	echo -n "Formatting $id ..."
	sgdisk --zap-all "$id"
	if [[ "$uefi" == "n" ]]; then
		sgdisk -a1 -n2:34:2047  -t2:EF02 "$id"
	else
		sgdisk     -n3:1M:+512M -t3:EF00 "$id"
	fi
	sgdisk         -n1:0:0      -t1:BF01 "$id"
	echo "Done."
done

command="zpool create -d -o feature@async_destroy=enabled -o feature@empty_bpobj=enabled -o feature@lz4_compress=enabled -o ashift=12 -O compression=lz4 -O atime=off $poolname mirror -f $ids_part1"
#        zpool create -d -o feature@async_destroy=enabled -o feature@empty_bpobj=enabled -o feature@lz4_compress=enabled -o ashift=12 -O compression=lz4 rpool /dev/sda3
#        zpool create -d -o feature@async_destroy=enabled -o feature@empty_bpobj=enabled -o feature@lz4_compress=enabled -o ashift=12 -O compression=lz4 -O copies=2 -O acltype=posixacl -O xattr=sa -O utf8only=on -O atime=off -O relatime=on rpool 

disk_status
color orange "$command"
yes_or_no "Is this OK?"
if [[ "$answer" != "y" ]]; then
	error "ABORTED: cancelled zfs creation"
fi

if $command; then
	color green "SUCCESS: zfs pool creation succeeded!"
else
	error "FAILURE: zfs pool creation failed!"
fi
zpool upgrade "$poolname"
zpool status -v "$poolname"
udevadm trigger

zfs create "$poolname/ROOT"
mkdir /mnt/tmp
mount --bind / /mnt/tmp
rsync -avPX /mnt/tmp/. "/$poolname/ROOT/."
umount /mnt/tmp

fstab=`cat "/$poolname/ROOT/etc/fstab"`
echo "$fstab" | awk '{print "#" $0}' > "/$poolname/ROOT/etc/fstab"

grubfile="/$poolname/ROOT/etc/default/grub"

# cat "$grubfile"
#GRUB_TIMEOUT=5
#GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
#GRUB_DEFAULT=saved
#GRUB_DISABLE_SUBMENU=true
#GRUB_TERMINAL_OUTPUT="console"
#GRUB_CMDLINE_LINUX="rd.lvm.lv=cl00/root rd.lvm.lv=cl00/swap rhgb quiet"
#GRUB_DISABLE_RECOVERY="true"

sed -i -e 's,rhgb quiet"$,rhgb quiet boot=zfs root=ZFS='"$poolname"'/ROOT",g' "$grubfile"
sed -i -e 's,GRUB_HIDDEN_TIMEOUT=0,#GRUB_HIDDEN_TIMEOUT=0,g' "$grubfile"
to_add='GRUB_PRELOAD_MODULES="part_gpt zfs"'
if ! grep -q "$to_add" "$grubfile"; then
	echo "$to_add" >> "$grubfile"
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

for dir in proc sys dev; do
	mount --bind "/$dir" "/$poolname/ROOT/$dir"
done

mych="chroot /$poolname/ROOT/"

#$mych export ZPOOL_VDEV_NAME_PATH=YES
$mych ln -s /dev/disk/by-id/* /dev/ -i
$mych mkdir /boot/grub2
$mych grub2-mkconfig -o /boot/grub2/grub.cfg
$mych grep ROOT /boot/grub2/grub.cfg ###!!!should return a few lines but doesn't

ids_dev=`echo "$ids" | sed "s,/disk/by-id,,g"`
for disk in $ids
do
  $mych grub2-install --boot-directory=/boot $disk
done

#no need to do this for later versions of centos:
#$mych echo 'add_dracutmodules+="zfs"' >> /etc/dracut.conf

$mych dracut -f -v /boot/initramfs-$(uname -r).img $(uname -r)

for dir in proc sys dev; do
	umount "/$poolname/ROOT/$dir"
done
