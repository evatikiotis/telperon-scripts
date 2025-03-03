#!/bin/bash
exec >installK3s.log
exec 2>&1

sudo apt-get update

sudo sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/" /etc/ssh/sshd_config
sudo adduser staginguser --gecos "First Last,RoomNumber,WorkPhone,HomePhone" --disabled-password
sudo echo "staginguser:ArcPassw0rd" | sudo chpasswd

# Injecting environment variables
# Check if the correct number of arguments are passed
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <adminUsername> <password> <templateBaseUrl>"
    exit 1
fi

# Injecting environment variables
cat <<EOF > vars.sh
#!/bin/bash
export adminUsername=$1
export password=$2
export templateBaseUrl=$3
EOF

chmod +x vars.sh
. ./vars.sh

export K3S_VERSION="1.28.5+k3s1" # Do not change!

# Creating login message of the day (motd)
sudo curl -v -o /etc/profile.d/welcomeK3s.sh ${templateBaseUrl}/scripts/welcomeK3s.sh

# Syncing this script log to 'jumpstart_logs' directory for ease of troubleshooting
sudo -u $adminUsername mkdir -p /home/${adminUsername}/jumpstart_logs
while sleep 1; do sudo -s rsync -a /var/lib/waagent/custom-script/download/0/installK3s.log /home/${adminUsername}/jumpstart_logs/installK3s.log; done &

# Installing Rancher K3s cluster (single control plane)
echo ""
publicIp=$(hostname -i)
sudo mkdir ~/.kube
sudo -u $adminUsername mkdir /home/${adminUsername}/.kube
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --node-external-ip ${publicIp}" INSTALL_K3S_VERSION=v${K3S_VERSION} sh -
sudo chmod 644 /etc/rancher/k3s/k3s.yaml
sudo kubectl config rename-context default arcbox-k3s --kubeconfig /etc/rancher/k3s/k3s.yaml
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo cp /etc/rancher/k3s/k3s.yaml /home/${adminUsername}/.kube/config
sudo cp /etc/rancher/k3s/k3s.yaml /home/${adminUsername}/.kube/config.staging
sudo chown -R $adminUsername /home/${adminUsername}/.kube/
sudo chown -R staginguser /home/${adminUsername}/.kube/config.staging

# Installing Helm 3
echo ""
sudo snap install helm --classic
echo "path to health-probe.yaml: ${templateBaseUrl}/manifests/health-probe.yaml"
kubectl create namespace health

kubectl apply -f ${templateBaseUrl}/manifests/health-probe.yaml
