# zfs-server-cluster-setup
A set of installation and setup scripts for creating a cluster of CentOS servers that boot from the ZFS filesystem.

## DeSCRIPTions

### ubuntu-zfs-setup.sh
Install Ubuntu with a ZFS filesystem. Should be run from a live USB (unlike the CentOS script) of the **desktop version** of Ubuntu. Tested and working with Ubuntu 16.04 and Ubuntu 18.04. Based on [this wiki article](https://github.com/zfsonlinux/pkg-zfs/wiki/HOWTO-install-Ubuntu-18.04-to-a-Whole-Disk-Native-ZFS-Root-Filesystem-using-Ubiquity-GUI-installer).

### ubuntu-admin-tools.sh
Install XRDP remote desktop, ssh access, firewall, utility packages, and xfce desktop settings.

### ubuntu-k8s-setup.sh
Install kubernetes using kubeadm to a node, either the master node or a worker node. The master node must be installed first, which will generate a "kubeadm join" command to be run on the worker nodes.

### install-common.sh
Common functions for all the scripts, such as output text coloring, error messages, and disk utilities

### centos-zfs-setup.sh
Install CentOS with a ZFS filesystem. Should be run from a CentOS installation, not a live USB. See the beginning of the script for instructions.
This script is not working and I have switched to Ubuntu for the setup. If you have a fix, submit a pull request.

## Future Scripts:
* backup-script-setup.sh -- Install a cron job that backs up the ZFS pool with [syncoid](https://github.com/jimsalterjrs/sanoid) to another location specified by the user.
* k8s-install.sh -- install kubectl, kubeadm, and kubefed packages from [kubernetes](https://kubernetes.io/).
* master-node-setup.sh -- set up a machine as a master node of a cluster and join a federated group of clusters in different locations using kubefed.
* worker-node-setup.sh -- set up a machine as a worker node and join the local cluster with kubeadm as specified by the master node.
* node-setup-common.sh -- a script that holds all the common elements between the worker and master nodes. This should not be called directly, the other scripts will call it as needed.

## Other Ideas
* config files to further automate the setup and to provide the same options to multiple scripts
* scripts to install monitoring tools that will email the user when ZFS has a fault or when a kubernetes node fails
* a way to remotely access the system with ssh tunneling if the machine becomes not externally accessible
