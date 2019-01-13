# zfs-server-cluster-setup
A set of installation and setup scripts for creating a cluster of CentOS servers that boot from the ZFS filesystem.

## DeSCRIPTions

### centos-zfs-setup.sh
Install CentOS with a ZFS filesystem. Should be run from a CentOS installation, not a live USB. See the beginning of the script for instructions.

### ubuntu-zfs-setup.sh
Install Ubuntu with a ZFS filesystem. Should be run from a live USB (unlike the CentOS script).

## Future Scripts:
* backup-script-setup.sh -- Install a cron job that backs up the ZFS pool with [syncoid](https://github.com/jimsalterjrs/sanoid) to another location specified by the user.
* admin-tools-setup.sh -- enable remote ssh login, install xrdp, tmux, and a way to remotely access the system with ssh tunneling if the machine becomes not externally accessible.
* k8s-install.sh -- install kubectl, kubeadm, and kubefed packages from [kubernetes](https://kubernetes.io/).
* master-node-setup.sh -- set up a machine as a master node of a cluster and join a federated group of clusters in different locations using kubefed.
* worker-node-setup.sh -- set up a machine as a worker node and join the local cluster with kubeadm as specified by the master node.
* node-setup-common.sh -- a script that holds all the common elements between the worker and master nodes. This should not be called directly, the other scripts will call it as needed.
* install-common.sh -- all the common functions to all the install sctipts such as text coloring and yes/no prompts

## Other Ideas
* Config files to further automate the setup and to provide the same options to multiple scripts
* Scripts to install monitoring tools that will email the user when ZFS has a fault or when a kubernetes node fails.
