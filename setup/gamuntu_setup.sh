#!/usr/bin/env bash

set -o errexit 
set -o errtrace 
set -o nounset 
set -o pipefail 
shopt -s expand_aliases
alias die='EXIT=$? LINE=$LINENO error_exit'
CROSS='\033[1;31m\xE2\x9D\x8C\033[0m'
CHECKMARK='\033[0;32m\xE2\x9C\x94\033[0m'
RETRY_NUM=5
RETRY_EVERY=3
trap die ERR
trap 'die "Script interrupted."' INT

function error_exit() {
  trap - ERR
  local DEFAULT='Unknown failure occured.'
  local REASON="\e[97m${1:-$DEFAULT}\e[39m"
  local FLAG="\e[91m[ERROR:LXC] \e[93m$EXIT@$LINE"
  msg "$FLAG $REASON"
  exit $EXIT
}
function msg() {
  local TEXT="$1"
  echo -e "$TEXT"
}

echo -e "${CHECKMARK} \e[1;92m Setting up Container OS... \e[0m"
sed -i "/$LANG/ s/\(^# \)//" /etc/locale.gen
locale-gen >/dev/null
while [ "$(hostname -I)" = "" ]; do
  1>&2 echo -e "${CROSS} \e[1;31m No Network: \e[0m $(date)"
  sleep $RETRY_EVERY
  ((NUM--))
  if [ $NUM -eq 0 ]
  then
    1>&2 echo -e "${CROSS} \e[1;31m No Network After $RETRY_NUM Tries \e[0m"
    exit 1
  fi
done
  echo -e "${CHECKMARK} \e[1;92m Network Connected: \e[0m $(hostname -I)"

echo -e "${CHECKMARK} \e[1;92m Updating Container OS \e[0m"
apt-get update &>/dev/null
apt-get -qqy upgrade &>/dev/null

echo -e "${CHECKMARK} \e[1;92m Installing Dependencies... \e[0m"
apt-get update &>/dev/null
apt-get -qqy install \
    curl \
    sudo \
    libnet-ssleay-perl \
    libauthen-pam-perl \
    libio-pty-perl \
    unzip \
    shared-mime-info &>/dev/null
    
echo -e "${CHECKMARK} \e[1;92m Downloading Webmin... \e[0m"
wget http://prdownloads.sourceforge.net/webadmin/webmin_1.984_all.deb &>/dev/null

echo -e "${CHECKMARK} \e[1;92m Installing Webmin... \e[0m"
dpkg --install webmin_1.984_all.deb &>/dev/null

echo -e "${CHECKMARK} \e[1;92m Setting Default Webmin usermame & password to root... \e[0m"
/usr/share/webmin/changepass.pl /etc/webmin root root &>/dev/null
rm -rf /root/webmin_1.984_all.deb
   
echo -e "${CHECKMARK} \e[1;92m Setting Up Hardware Acceleration... \e[0m"  
apt-get -y install \
    va-driver-all \
    ocl-icd-libopencl1 \
    beignet-opencl-icd &>/dev/null
    
/bin/chgrp video /dev/dri
/bin/chmod 755 /dev/dri
/bin/chmod 660 /dev/dri/*
    
echo -e "${CHECKMARK} \e[1;92m Customizing Docker... \e[0m"
DOCKER_CONFIG_PATH='/etc/docker/daemon.json'
mkdir -p $(dirname $DOCKER_CONFIG_PATH)
cat >$DOCKER_CONFIG_PATH <<'EOF'
{
  "log-driver": "journald"
}
EOF

echo -e "${CHECKMARK} \e[1;92m Installing Docker... \e[0m"
sh <(curl -sSL https://get.docker.com) &>/dev/null

echo -e "${CHECKMARK} \e[1;92m Installing Docker Compose... \e[0m"
curl -L "https://github.com/docker/compose/releases/download/2.2.3/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose &>/dev/null
chmod +x /usr/local/bin/docker-compose &>/dev/null

echo -e "${CHECKMARK} \e[1;92m Customizing LXC... \e[0m"
chmod -x /etc/update-motd.d/*
touch ~/.hushlogin
GETTY_OVERRIDE="/etc/systemd/system/container-getty@1.service.d/override.conf"
mkdir -p $(dirname $GETTY_OVERRIDE)
cat << EOF > $GETTY_OVERRIDE
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear --keep-baud tty%I 115200,38400,9600 \$TERM
EOF
systemctl daemon-reload
systemctl restart $(basename $(dirname $GETTY_OVERRIDE) | sed 's/\.d//')

echo -e "${CHECKMARK} \e[1;92m Cleanup... \e[0m"
rm -rf /gamuntu_setup.sh /var/{cache,log}/* /var/lib/apt/lists/*
