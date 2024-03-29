#!/bin/bash

sudo apt-get update 
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do 
  sudo apt-get remove -y $pkg
done
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
"deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
"$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo apt-get autoremove -y
sudo systemctl start docker
sudo systemctl enable docker

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl

curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

sudo usermod -aG root devops
sudo usermod -aG docker devops

sudo -i -u devops bash << K3D
k3d cluster create traive-interview --api-port 6443 --servers 1 --agents 1 --port "30500-31000:30500-31000@server:0"
K3D
