#!/bin/bash

# Take the user input for the dockerhub username (in a while loop with regex validation)
while true; do
  read -p "Enter the username: " username
  if [[ $dockerhub_username =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{3,})$ ]]; then
    break
  else
    echo "Invalid username. Please try again."
  fi
done

# Take the user input for the dockerhub password (in a while loop with regex validation)
while true; do
  read -p "Enter the password: " password
  if [[ $dockerhub_password =~ ^.{8,}$ ]]; then
    break
  else
    echo "Invalid password. Please try again."
  fi
done

# Find the largest drive and store it as a variable (linux)
largest_drive=$(lsblk -bno SIZE,NAME | sort -nr | awk 'NR==1 {print $2}')

sudo snap install microk8s --classic --channel=1.30
sudo usermod -a -G microk8s $USER
mkdir -p ~/.kube
chmod 0700 ~/.kube
su - $USER  
microk8s status --wait-ready

# add dockerhub credentials to containerd microk8s config
bash -c "echo '[plugins.\"io.containerd.grpc.v1.cri\".registry.configs.\"registry-1.docker.io\".auth]
username = \"$dockerhub_username\"
password = \"$dockerhub_password\"' | sudo tee -a /var/snap/microk8s/current/args/containerd-template.toml > /dev/null"



microk8s stop 
microk8s start


# Enable microk8s addons use for cinco-de-bio
sudo microk8s enable dns
sudo microk8s enable ingress
sudo microk8s enable metrics-server
sudo microk8s enable registry
sudo microk8s enable hostpath-storage
sudo microk8s enable storage

microk8s status --wait-ready
# Adding the CincoDeBio Helm Chart Repo
microk8s helm repo add scce https://colm-brandon-ul.github.io/cincodebio-helm-chart
microk8s helm repo update
# Installing CincoDeBio Cores Services
echo "Installing CincoDeBio Cores Services, this may take a few minutes"

# need to set the Dockerhub username and password here via --set flag
microk8s helm install --wait my-cinco-de-bio scce/cinco-de-bio --set global.containers.docker_hub_username=$dockerhub_username --set global.containers.docker_hub_password=$dockerhub_password

# Need to get the Ingress IP address
