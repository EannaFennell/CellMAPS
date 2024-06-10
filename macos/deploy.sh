#!/bin/bash

# Take the user input for the dockerhub username (in a while loop with regex validation)
while true; do
  read -p "Enter the username: " dockerhub_username
  if echo "$dockerhub_username" | grep -Eq '^[a-zA-Z0-9](?:[a-zA-Z0-9-]{3,})$'; then
    break
  else
    echo "Invalid Username. Please try again."
  fi
done

# Take the user input for the dockerhub password (in a while loop with regex validation)
while true; do
  read -p "Enter the password: " dockerhub_password
  if echo "$dockerhub_password" | grep -Eq '^.{8,}$'; then
    break
  else
    echo "Invalid password. Please try again."
  fi
done

#check number of cpu cores
total_cpu_cores=$(sysctl -n hw.ncpu)
echo "Number of CPU cores: $total_cpu_cores"
# check memory
total_memory=$(sysctl -n hw.memsize)
total_memory_gb=$(echo "scale=2; $total_memory / 1024^3" | bc)
# check disk space
total_disk_space=$(df -h / | tail -1 | awk '{print $4}')

# get inputs from user (as to how much resources to allocate to the multipass VM)
echo "Enter the number of CPU cores to allocate to the CincoDeBio Cluster (Total Available = $total_cpu_cores): "
# read value, constraints: 2 <= value <= total_cpu_cores
while true; do
    read cpu_cores
    if [ $cpu_cores -ge 2 ] && [ $cpu_cores -le $total_cpu_cores ]; then
        break
    else
        echo "Invalid input. Please enter a value between 2 and $total_cpu_cores: "
    fi
done

echo "Enter the amount of memory to allocate to the CincoDeBio Cluster (Total Available = $total_memory_gb GB): "
# read value, constraints: 4 <= value <= total_memory_gb
while true; do
    read memory_gb
    if (( $(echo "$memory_gb >= 4" | bc -l) )) && (( $(echo "$memory_gb <= $total_memory_gb" | bc -l) )); then

        break
    else
        echo "Invalid input. Please enter a value between 4 and $total_memory_gb: "
    fi
done

# read disk space, constraints: 30 <= value <= total_disk_space
echo "Enter the amount of disk space to allocate to the CincoDeBio Cluster (Total Available = $total_disk_space): "
while true; do
    read disk_space
    # Remove 'Gi' from the input and total disk space
    disk_space_int=${disk_space%Gi}
    total_disk_space_int=${total_disk_space%Gi}
    if [ $disk_space_int -ge 20 ] && [ $disk_space_int -le $total_disk_space_int ]; then
        break
    else
        echo "Invalid input. Please enter a value between 20 and $total_disk_space: "
    fi
done

echo "Disk space to allocate: $disk_space_int"

# Check if home brew is install (if not install it)

if which brew >/dev/null; then
    echo "Homebrew is installed."
else
    echo "Homebrew is not installed."
    echo "Installing Homebrew..."
    CI=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi


# Check if multipass is installed (if not install it)
if which multipass >/dev/null; then
    echo "Multipass is installed."
else
    echo "Multipass is not installed."
    echo "Installing Multipass..."
    brew install --cask multipass
fi

# Check if Microk8s is installed (if not install it)
if which microk8s >/dev/null; then
    echo "MicroK8s is already installed."
    # Setting up microk8s VM
    echo "Starting MicroK8s..."
    microk8s install --cpu $cpu_cores --mem $memory_gb --disk $disk_space_int --channel 1.28/stable --image 22.04 --assume-yes
    multipass exec microk8s-vm -- sudo snap install microk8s --classic
    multipass exec microk8s-vm -- sudo microk8s status --wait-ready
else
    echo "Microk8s is not installed."
    echo "Installing MicroK8s..."
    brew install ubuntu/microk8s/microk8s
    echo "Starting MicroK8s..."
    microk8s install --cpu $cpu_cores --mem $memory_gb --disk $disk_space_int --channel 1.28/stable --image 22.04 --assume-yes
    multipass exec microk8s-vm -- sudo snap install microk8s --classic
    multipass exec microk8s-vm -- sudo microk8s status --wait-ready
fi

 # get the IP address of the VM
VM_IP=$(multipass info microk8s-vm | grep IPv4 | awk '{print $2}')

microk8s enable dns
microk8s enable ingress
microk8s enable metrics-server
microk8s enable registry
microk8s enable hostpath-storage
microk8s enable storage

# Add dockerhub credentials to microk8s cluster
multipass exec microk8s-vm -- bash -c "echo '[plugins.\"io.containerd.grpc.v1.cri\".registry.configs.\"registry-1.docker.io\".auth]
username = \"$dockerhub_username\"
password = \"$dockerhub_password\"' | sudo tee -a /var/snap/microk8s/current/args/containerd-template.toml > /dev/null"

# restart cluster
microk8s stop
microk8s start

microk8s status --wait-ready
# Adding the CincoDeBio Helm Chart Repo
microk8s helm repo add scce https://colm-brandon-ul.github.io/cincodebio-helm-chart
microk8s helm repo update
# Installing CincoDeBio Cores Services
echo "Installing CincoDeBio Cores Services, this may take a few minutes"

# need to set the Dockerhub username and password here via --set flag
microk8s helm install --wait my-cinco-de-bio scce/cinco-de-bio --set global.containers.docker_hub_username=$dockerhub_username --set global.containers.docker_hub_password=$dockerhub_password


echo "CincoDeBio Cluster is ready for use. IP Address: $VM_IP (Copy this into the CincoDeBio Preferences)"
echo "URL to Upload Portal (Copy this URL into your browser): http://$VM_IP/data-manager/"
echo "The Application may take a few minutes to start up. \n Happy Modelling!"
