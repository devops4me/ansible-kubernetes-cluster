
Tired of paying through the nose for a cloud kubernetes cluster. Fancy mining bitcoin with your own server rack. How about creating a **[Raspberry Pi Kubernetes Cluster](https://www.devopswiki.co.uk/wiki/kubernetes/pi/raspberry-pi-kubernetes-cluster)**

# Use Ansible to Install Kubernetes on Vagrant VMs

This Ansible configuration manager will create a Kubernetes cluster on cloud VMs, vagrant VMs or even a Raspberry Pi cluster.

## 1. Create and Validate the Ansible Inventory

To create the Ansible inventory the steps are

- run **`vagrant ssh-config`** to list the ports and the paths to the ssh private keys
- create the section inside the **`~/.ssh/config**` file (see below)
- verify you can ssh into the machines with **`vagrant ssh master`** and similar for the workers
- verify you can ssh with **`ssh vagrant@kubemaster`** and similar for the workers
- create the Ansible inventory **`hosts.ini`** file
- validate the inventory with **`ansible -m ping all -i hosts.ini`**


### The SSH Config File

Put this section inside the **`~/.ssh/config**` file to help Ansible configure the kubernetes cluster machines.

```
Host kubemaster
HostName 127.0.0.1
User vagrant
Port <master_port>
IdentityFile </path/to/master/private/key>
StrictHostKeyChecking no

Host kubeworker1
HostName 127.0.0.1
User vagrant
Port <worker1_port>
IdentityFile </path/to/worker1/private/key>
StrictHostKeyChecking no

Host kubeworker2
HostName 127.0.0.1
User vagrant
Port <worker2_port>
IdentityFile </path/to/worker2/private/key>
StrictHostKeyChecking no
```

### The Ansislbe Inventory (Hosts) File

Create this inventory (hosts) file. The **`ansible_host`** refers to the **`Host`** variable inside the **`~/.ssh/config`** file.

```
master ansible_host=kubemaster
worker ansible_host=kubeworker1
worker ansible_host=kubeworker2
```

Now validate the inventory with **`ansible -m ping all -i hosts.ini`**.


---

## How to Determine Versions

Sometimes Kubernetes (via the **`kubeadm init`** does not like the docker version. To change it you need to ssh into all nodes and

- **`sudo apt-cache showpkg docker-ce`** - discover the available versions
- read the error and reset the version within the Install docker task
- **`sudo apt-get remove docker-ce --assume-yes`** - remove the current docker-ce package
- **`sudo apt autoremove docker-ce --assume-yes`** - and again
- **`sudo apt-get remove docker-ce-cli --assume-yes`** - remove the current docker-ce-cli package
- **`sudo apt autoremove docker-ce-cli --assume-yes`** - and again




## Create the Ansible Playbooks that provision Kubernetes

There are 3 key playbooks that will provision the kubernetes cluster. The steps to creating them are

- create the Ansible dependencies.yml file
- create the Ansible cluster **`kubemaster.yml`** file
- create the Ansible cluster **`kubeworker.yml`** file


### The Ansible dependencies.yml playbook

The dependencies playbook installs necessary software on the masters and workers and also ensures that swapfiles are removed.

```
- hosts: all
  become: yes
  tasks:

  - name: install Aptitude
    apt:
      name: aptitude
      state: present
      update_cache: true

  - name: install Docker
    apt:
      name: docker.io
      state: present
      update_cache: false

  - name: Install Transport HTTPS
    apt:
      name: apt-transport-https
      state: present

  - name: install kubelet
    apt:
      name: kubelet
      state: present
      update_cache: false

  - name: install kubeadm
    apt:
      name: kubeadm
      state: present

  - name: Remove swapfile from /etc/fstab
    mount:
      name: "{{ item }}"
      fstype: swap
      state: absent
    with_items:
      - swap
      - none

  - name: Disable swap
    command: swapoff -a
    when: ansible_swaptotal_mb > 0

  - name: add Kubernetes apt-key
    apt_key:
      url: "https://packages.cloud.google.com/apt/doc/apt-key.gpg"
      state: present

  - name: add Kubernetes' APT repository
    apt_repository:
      repo: deb http://apt.kubernetes.io/ kubernetes-xenial main
      state: present
      filename: 'kubernetes'

- hosts: master
  become: yes
  tasks:

  - name: install kubectl
    apt:
      name: kubectl
      state: present
      force: yes
```

You can validate the dependencies using **`ansible-playbook -i hosts.ini dependencies.yml`**

### The Ansible kubemaster.yml playbook

This playbook provisions the kubernetes master nodes and sets up the pod network.

```
- hosts: master
  become: yes
  tasks:

    - name: Add the "kube" group
      group:
        name: kube
        state: present

    - name: Add the user "kube"
      user:
        name: kube
        comment: Kubernetes user
        group: kube

    - name: initialize the cluster
      shell: kubeadm init --pod-network-cidr=10.99.0.0/16 >> cluster_init.txt
      args:
        chdir: $HOME
        creates: cluster_init.txt

    - name: create .kube directory
      become: yes
      become_user: kube
      file:
        path: $HOME/.kube
        state: directory
        mode: 0755

    - name: copy admin.conf to user's kube config
      copy:
        src: /etc/kubernetes/admin.conf
        dest: /home/kube/.kube/config
        remote_src: yes
        owner: kube

    - name: install Pod network
      become: yes
      become_user: kube
      shell: kubectl apply -f https://docs.projectcalico.org/v3.14/manifests/calico.yaml >> pod_network_setup.txt
      args:
        chdir: $HOME
        creates: pod_network_setup.txt
```

You can validate the master provisioning playbook using **`ansible-playbook -i hosts.ini kubemaster.yml`**

### Create the Kubernetes workers playbook

The kubernetes workers playbook is mainly focused on getting the worker to join the cluster by taking the join command from one (master) and giving it to the worker in question.

```
- hosts: master
  become: yes
  gather_facts: false

  tasks:
    - name: get join command
      become_user: kube
      shell: kubeadm token create --print-join-command --description "Generated by Ansible"
      register: generated_join_command

    - name: grab join command
      set_fact:
        join_command: "{{ generated_join_command.stdout_lines[0] }}"

- hosts: worker
  become: yes
  tasks:

    - name: join cluster
      shell: "{{ hostvars['master'].join_command }} >> node_join.txt"
      args:
        chdir: $HOME
        creates: node_join.txt
```

You can validate the worker joining playbook using **`ansible-playbook -i hosts.ini kubeworker.yml`**


---


## Accessing the Kubernetes Cluster

To access the cluster properly you should export the **`~/.kube/config`** file from the master onto your host laptop which needs to have kubectl installed. Now **`kubectl get nodes`** should return something sensible.

Initially to access the cluster you
- ssh into the master **`vagrant ssh master`**
- become the kube user **`sudo su kube`**
- run **`kubectl get nodes`**

Now your cluster is ready for lots of learning, validating and provisioning in a local setting without the hefty cloud fees.


## Kubernetes Cluster Internet Resources

This is the only resource that works out of the box with one **`vagrant up`** command. However there are still some great references pages where authors have built kubernetes clusters with Ansible and Vagrant.

- **[Create Kubernetes Cluster from IT WonderLab](https://www.itwonderlab.com/ansible-kubernetes-vagrant-tutorial/)**
- **[Install Calico Networking for On-Premise Deployments](https://docs.projectcalico.org/getting-started/kubernetes/self-managed-onprem/onpremises)**
- **[Kubernetes Vagrant and Ansible Github Repo](https://github.com/ctienshi/kubernetes-ansible/tree/master/centos)**
- **[Ansible Official User Guide](https://docs.ansible.com/ansible/latest/user_guide/index.html)**
- **[Installing Kubernetes on Docker](https://www.howtoforge.com/tutorial/how-to-install-kubernetes-on-ubuntu/)**
- **[Out of Date Kubernetes Guide using Ubuntu 16.04](https://kubernetes.io/blog/2019/03/15/kubernetes-setup-using-ansible-and-vagrant/)**
- **[Medium Kubernetes Cluster with Vagrant and Ansible](https://medium.com/@MonadicT/create-a-kubernetes-cluster-with-vagrant-and-ansible-88af7948a1fc)**
- **[Using Ansible to Create a Kubernetes Virtual Lab](https://graspingtech.com/create-kubernetes-cluster/)**
- **[Create a Kubernetes Cluster on Vagrant using Ansible](https://jeremievallee.com/2017/01/31/kubernetes-with-vagrant-ansible-kubeadm.html)**
- **[Create a Standalone Kubernetes Cluster with Vagrant](https://nextbreakpoint.com/posts/article-create-standalone-kubernetes-cluster-with-vagrant.html)**
