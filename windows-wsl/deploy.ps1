# May need to edit WSL Config file to allow max memory / cpu usage
# install / update WSL2
wsl.exe --update
# Global Variables
$distro = "Ubuntu-22.04"
# Get system name
$systemName = $(hostname)
# apply regex to system name to make sure it's lowercase letters, numbers and hyphens only
$hostnameValid = $($systemName -match "[a-z0-9\-]+")

if (!$hostnameValid) {
    Write-Output "Hostname is invalid. Exiting."
    exit
    # Logic for changing the hostname
}

# Find the Drive with most available space
$drives = Get-PSDrive -PSProvider FileSystem | Where-Object {$_.Free -ne $null}
$largestDrive = $drives | Sort-Object -Property Free -Descending | Select-Object -First 1
# Get the root of the largest drive
Write-Output $largestDrive.Root

# Make folder(s) for WSL VHD migration
$wslRoot = "$($largestDrive.Root)wsl"
$wslBackup = "$($largestDrive.Root)wsl-backup"
# make the folder if it doesn't exist
if (!(Test-Path -Path $wslRoot)) {
    New-Item -Path $wslRoot -ItemType Directory
}
if (!(Test-Path -Path $wslBackup)) {
    New-Item -Path $wslBackup -ItemType Directory
}

# Installing Ubuntu # wait for the above to finish
wsl.exe --install -d $distro

Write-Output "WSL will open a separate window to complete the $distro installation"
Write-Output "Navigate to other window to complete. This requires setting a Username and Password"
Write-Output "When you have completed that step, return to this window and press Enter to continue"
# wait for input
# sleep for 20 seconds
Start-Sleep -Seconds 20
Read-Host "Press Enter to continue"
wsl.exe --update
wsl.exe --set-version $distro 2
wsl.exe --set-default-version 2
wsl.exe --set-default $distro
Write-Output "You will be prompted to enter the password for the user you created in the Ubuntu installation"
wsl.exe -d $distro sudo apt update
wsl.exe -d $distro sudo apt upgrade -y
# entering in the password for the second command is not necessary
# wsl.exe sudo echo -e "[boot]\\nsystemd=true" | wsl.exe sudo tee /etc/wsl.conf
wsl.exe sudo sh -c 'echo \"[boot] \nsystemd=true\" > /etc/wsl.conf'

wsl.exe --shutdown

# assume input is invalid
$valid_username = 0
$valid_password = 0

# loop the input until it's valid
while (-not $valid_username) {
    # read username input
    $dockerhub_username = Read-Host "Enter your DockerHub username"
    # check if the username is valid
    $valid_username = $dockerhub_username -match "^[a-zA-Z0-9]([a-zA-Z0-9-]{3,})$"
}

while (-not $valid_password) {
    # read password input
    $dockerhub_password = Read-Host "Enter your DockerHub password"
    # check if the password is valid
    $valid_password = $dockerhub_password -match "^.{8,}$"
}

# perhaps should do a test auth here

# install microk8s
wsl.exe sudo snap install microk8s --classic
Write-Output "Microk8s is now installed. Waiting for it to be ready"
wsl.exe sudo microk8s status --wait-ready

wsl.exe sudo microk8s kubectl get node -o wide
wsl.exe sudo bash -c "echo '# Docker Hub Credentials' >> /var/snap/microk8s/current/args/containerd-template.toml"

$command = @"
echo '[plugins.\"io.containerd.grpc.v1.cri\".registry.configs.\"registry-1.docker.io\".auth]
username = \"{0}\"
password = \"{1}\"' >> /var/snap/microk8s/current/args/containerd-template.toml
"@ -f $dockerhub_username, $dockerhub_password
# update the containerd config
wsl.exe sudo bash -c $command

# restart microk8s
wsl.exe sudo microk8s stop
wsl.exe sudo microk8s start

Write-Output "Now migrating the WSL VHD to the largest drive - $($largestDrive.Root)"

wsl.exe --export $distro "$wslBackup\$distro.tar"
# delete the distro and reimport it to the new location
wsl.exe --unregister $distro
wsl.exe --import $distro $wslRoot "$wslBackup\$distro.tar"

# This variable needs to be stored now, as the IP address will change after the next command
$ip_address = $(wsl -d $distro hostname -I)

# Enable microk8s addons use for cinco-de-bio
wsl.exe -d $distro sudo microk8s enable dns
wsl.exe -d $distro sudo microk8s enable ingress
wsl.exe -d $distro sudo microk8s enable metrics-server
wsl.exe -d $distro sudo microk8s enable registry
wsl.exe -d $distro sudo microk8s enable hostpath-storage
wsl.exe -d $distro sudo microk8s enable storage

Write-Output "Restarting Microk8s. Waiting for it to be ready"
wsl.exe sudo microk8s status --wait-ready
# Adding the CincoDeBio Helm Chart Repo
wsl.exe sudo microk8s helm repo add scce https://colm-brandon-ul.github.io/cincodebio-helm-chart
wsl.exe sudo microk8s helm repo update
# Installing CincoDeBio Cores Services
Write-Output "Installing CincoDeBio Cores Services, this may take a few minutes"

# need to set the Dockerhub username and password here via --set flag
wsl.exe sudo microk8s helm install --wait my-cinco-de-bio scce/cinco-de-bio --set global.containers.docker_hub_username=$dockerhub_username --set global.containers.docker_hub_password=$dockerhub_password

# wait for the above to finish

# Clear Output from Shell
Clear-Host

# Write Outputs
Write-Output "URL to Upload Portal (Copy this URL into your browser): http://$ip_address/data-manager/"
Write-Output "The CincoDeBio Cluster has started. IP Address: $ip_address (Copy this IP Address into the CincoDeBio Preferences in the Modelling Application)"
Write-Output "The CincoDeBio Cores Services are now being installed, this may take a few minutes"
Read-Host "Press Enter to Quit"
