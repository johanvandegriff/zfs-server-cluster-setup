#!/bin/bash

########################################################################
#
# This script follows a guide to install kubernetes on Ubuntu:
# https://kubernetes.io/docs/setup/independent/install-kubeadm/
# And another guide to create a cluster with kubeadm:
# https://kubernetes.io/docs/setup/independent/create-cluster-kubeadm/
#
########################################################################

. `dirname "$0"`/install-common.sh || exit 1

device=$(ip addr | grep -B 3 '[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+' | grep '^[0-9]:' | grep -v 'lo: ' | awk '{print $2}' | tr -d :)
mac_addr=$(ip addr show "$device" | grep '..:..:..:..:..:..' | awk '{print $2}')
uuid=$(cat /sys/class/dmi/id/product_uuid) || error "Error getting uuid. Maybe run this script with sudo?"

color yellow "Make sure the following info is unique for every node. If this is the first node, you should run this script with the --check option on the other nodes now before proceeding. This will just print out their respective MAC addresses and UUID's without installing anything."
echo "MAC ADDRESS:  $mac_addr"
echo "PRODUCT UUID: $uuid"

if [[ "$1" == "--check" ]]; then
    color green "--check specified; exiting after displaying info"
    exit 0
fi

color green "Press ENTER to continue."
read a

yes_or_no "Is this the master node? The master node must be initialized before all the other nodes."
master="$answer"

#https://kubernetes.io/docs/setup/independent/install-kubeadm/#check-required-ports
#Protocol	Direction	Port Range	Purpose	Used By
#TCP	Inbound	6443*	Kubernetes API server	All
#TCP	Inbound	2379-2380	etcd server client API	kube-apiserver, etcd
#TCP	Inbound	10250	Kubelet API	Self, Control plane
#TCP	Inbound	10251	kube-scheduler	Self
#TCP	Inbound	10252	kube-controller-manager	Self
#Worker node(s)
#Protocol	Direction	Port Range	Purpose	Used By
#TCP	Inbound	10250	Kubelet API	Self, Control plane
#TCP	Inbound	30000-32767	NodePort Services**	All

error_ports() {
    error "Error opening port(s): $@"
}

if [[ "$master" == y ]]; then
    ufw allow 6443/tcp || error_ports 6443
    ufw allow 2379:2380/tcp || error_ports 2379:2380
    ufw allow 10250:10252/tcp || error_ports 10250:10252
else
    ufw allow 10250/tcp || error_ports 10250
    ufw allow 30000:32767/tcp || error_ports 30000:32767
fi

color green "Installing kubernetes packages..."
apt-get update || error "Error with apt update (before adding k8s)"
apt-get install -y apt-transport-https curl || error "Error installing apt-transport-https and curl"
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - || error "Error downloading and adding k8s signing key"
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list || error "Error adding k8s to sources list"
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
apt-get update || error "Error with apt update (after adding k8s)"
apt-get install -y kubelet kubeadm kubectl || error "Error installing kubelet, kubeadm, and kubectl"
apt-mark hold kubelet kubeadm kubectl || error "Error telling apt to not automatically upgrade k8s packages"

#install docker-ce
#https://docs.docker.com/install/linux/docker-ce/ubuntu/
color green "Installing docker-ce..."
apt-get update || error "Error with apt update (before installing docker-ce)"
apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common || error "Error installing dependencies for docker-ce"
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - || error "Error adding docker's gpg key"
apt-key fingerprint 0EBFCD88 || error "Error looking for key fingerprint"
color yellow "Make sure the previous command outputted a matching fingerprint for docker. You can do this by looking up the fingerprint online to verify from multiple sources"
color green "Press ENTER to continue"
read a
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" || error "Error adding docker repositorty"
apt-get update || error "Error with apt update (during installation of docker-ce)"
apt-get install -y docker-ce || error "Error installing docker-ce"
docker run hello-world || error "Error running Hello World docker image"
color green "docker is installed"

#https://kubernetes.io/docs/setup/independent/create-cluster-kubeadm/
if [[ "$master" == y ]]; then
    kubeadm init || error "Error initializing kubeadm"
    color yellow "IMPORTANT: Copy the \"kubeadm join\" command above to a secure location (e.g. a password manager such as KeepassXC). You will need it when you add worker nodes to the cluster later."
    color green "Press ENTER when done."
    read a
    mkdir -p $HOME/.kube || error "Error creating ~/.kube"
    cp -i /etc/kubernetes/admin.conf $HOME/.kube/config || error "Error copying admin configuration to ~/.kube/"
    chown $(id -u):$(id -g) $HOME/.kube/config || error "Error changing ownership of ~/kube/"
    
    #for the pod network, I selected weave
    #this module is needed for the iptables command to work: https://serverfault.com/questions/697942/centos-6-elrepo-kernel-bridge-issues
    modprobe br_netfilter || error "Error enabling kernel module br_netfilter"
    sysctl net.bridge.bridge-nf-call-iptables=1 || error "Error setting bridge network option"
    kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')" || error "Error applying weave pod networking to kubeadm"
    while true; do
        kubectl get pods --all-namespaces || error "Error getting pods from kubeadm"
        color yellow "CoreDNS should be listed above. If all status lines are \"RUNNING\", type \"done\" and press ENTER. Otherwise, press ENTER to refresh the status until they are all ready"
        read answer
        if [[ "$answer" == "done" ]]; then
            break
        fi
    done
    yes_or_no "Do you want to schedule pods on the master node?"
    if [[ "$answer" == "y" ]]; then
        kubectl taint nodes --all node-role.kubernetes.io/master- || error "Error tainting the master node to enable scheduling pods"
    fi
    color green "Master node setup finished"
else
    color green "Enter the kubeadm join command that the master node outputted. This is in the format:
    kubeadm join --token <token> <master-ip>:<master-port> --discovery-token-ca-cert-hash sha256:<hash>
which was displayed when you installed kubeadm on the master node. The tokens can also be shown with:
    kubeadm token list
By default, tokens expire after 24 hours. A new token can be generated on the master node with:
    kubeadm token create
More info: https://kubernetes.io/docs/setup/independent/create-cluster-kubeadm/#join-nodes"
    read command
    $command || error "Error adding node to kubeadm cluster"
    color green "Node added. Check 'kubectl get nodes' on the master node to see it"
fi