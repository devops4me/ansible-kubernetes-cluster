Deploy a pod network

Next step is to deploy a pod network. The pod network is used for communication between hosts and is necessary for the Kubernetes cluster to function properly. For this we will use the Flannel pod network. Issue the following two commands on the master node:

kubernetes-master:~$ kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
kubernetes-master:~$ kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/k8s-manifests/kube-flannel-rbac.yml
