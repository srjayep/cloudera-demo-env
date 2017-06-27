#!/bin/sh

# logging stdout/stderr
set -x
exec >> /root/instance-postcreate-cdsw.log 2>&1
date

# Check CDSW node identifier set by bootstrap-cdsw-init.sh
if [ ! -e /root/cdsw ]; then
echo "This is not a cdsw node."
exit 0
fi

# install git
yum -y install git

# install dnsmasq
yum -y install dnsmasq
systemctl start dnsmasq

# Add DNS(dnsmasq on local)
perl -pi -e "s/nameserver/nameserver $(hostname -i)\nnameserver/" /etc/resolv.conf
chattr +i /etc/resolv.conf 

# This domain for DNS and is unrelated to Kerberos or LDAP domains.
DOMAIN="cdsw.$(hostname -i).xip.io"

# IPv4 address for the master node that is reachable from the worker nodes.
#
# Within an AWS VPC, MASTER_IP should be set to the internal IP
# of the master node; for instance, "10.251.50.12" corresponding to
# master node name of ip-10-251-50-12.ec2.internal.
MASTER_IP=$(hostname -i)

# Block device(s) for Docker images (space separated if multiple).
#
# These block devices cannot be partitions and should be at least 500GB. SSDs
# are strongly recommended.
#
# Use the full path, for instance "/dev/xvde".
DOCKER_BLOCK_DEVICES="$(grep '^/dev' /etc/fstab | cut -f1 -d' ' | sort | tail -n +2 | tr '\n' ' ')"

# (Not recommended, Master Only) One Block device for application state.
#
# If omitted, the filesystem mounted at /var/lib/cdsw on the master node
# will be used to store all user data. Cloudera *strongly* recommends
# that you mount a high reliability filesystem with backups configured.
# See the Cloudera Data Science Workbench documentation for sizing
# recommendations.
#
# If set, Cloudera Data Science Workbench will format the provided block
# device as ext4, mount it to /var/lib/cdsw and store all user data on it.
# This block device should be at least 500GB, and potentially significantly
# larger to scale with the number of projects expected.  An SSD is strongly
# recommended. This option is provided for convenience in demonstration or
# evaluation setups only, Cloudera is not responsible for data loss.
#
# Use the full path, for instance "/dev/xvdf".
APPLICATION_BLOCK_DEVICE="$(grep '^/dev' /etc/fstab | cut -f1 -d' ' | sort | head -1)"

# e.g.)
# cat /etc/fstab 
# ...
# /dev/xvdi /data0 ext4 defaults,noatime 0 0
# /dev/xvdh /data1 ext4 defaults,noatime 0 0
# /dev/xvdg /data2 ext4 defaults,noatime 0 0
# /dev/xvdf /data3 ext4 defaults,noatime 0 0
# 
# $(grep '^/dev' /etc/fstab | cut -f1 -d' ' | sort | head -1) command gets "/dev/xvdf"
# $(grep '^/dev' /etc/fstab | cut -f1 -d' ' | sort | tail -n +2 | tr '\n' ' ') command gets "/dev/xvdg /dev/xvdh /dev/xvdi"


# Configuring /etc/cdsw/config/cdsw.conf
perl -pi -e "s/DOMAIN=.*/DOMAIN=\"${DOMAIN}\"/" /etc/cdsw/config/cdsw.conf
perl -pi -e "s/MASTER_IP=.*/MASTER_IP=\"${MASTER_IP}\"/" /etc/cdsw/config/cdsw.conf
perl -pi -e "s|DOCKER_BLOCK_DEVICES=.*|DOCKER_BLOCK_DEVICES=\"${DOCKER_BLOCK_DEVICES}\"|" /etc/cdsw/config/cdsw.conf
perl -pi -e "s|APPLICATION_BLOCK_DEVICE=.*|APPLICATION_BLOCK_DEVICE=\"${APPLICATION_BLOCK_DEVICE}\"|" /etc/cdsw/config/cdsw.conf
for dev in $(grep '^/dev' /etc/fstab | cut -f1 -d' '); do umount $dev; done
sed -i '/^\/dev/d' /etc/fstab

# cdsw init - preinstall-validation - doesn't allow SELinux "permissive"
perl -pi -e "s/getenforce/#getenforce/" /etc/cdsw/scripts/preinstall-validation.sh

# cdsw init - preinstall-validation - doesn't allow IPv6
echo "net.ipv6.conf.all.disable_ipv6=0" >> /etc/sysctl.conf

# 
echo | cdsw init