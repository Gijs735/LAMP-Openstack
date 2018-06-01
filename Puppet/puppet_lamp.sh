## create instance
echo "What is your current user's name?"
read CURUSER
ssh-keygen
ssh-add '/home/$CURUSER/.ssh/id_rsa' 
openstack keypair create --public-key ~/.ssh/id_rsa.pub mykey
openstack security group create puppet
openstack security group rule create --proto icmp puppet
openstack security group rule create --proto tcp --dst-port 22 puppet
openstack security group rule create --proto tcp --dst-port 80 puppet
openstack security group rule create --proto tcp --dst-port 443 puppet

openstack server create --flavor m1.small --image "Ubuntu Xenial 16.04"  --nic net-id=network --security-group puppet --key-name mykey puppetclient

## create and associate floating ip ##

INSTANCE_NAME="puppetclient"
CC_PUBLIC_NETWORK_ID="vlan1288"
echo Getting floating ip id.
CC_FLOATING_IP_ID=$( openstack floating ip list -f value -c ID --status 'DOWN'  | head -n 1 )
if [ -z "$CC_FLOATING_IP_ID" ]; then
    echo No floating ip found creating a floating ip:
    openstack floating ip create "$CC_PUBLIC_NETWORK_ID" 
    echo Getting floating ip id:
    CC_FLOATING_IP_ID=$( openstack floating ip list -f value -c ID --status 'DOWN'  | head -n 1 )
fi

echo Getting public ip.
CC_PUBLIC_IP=$( openstack floating ip show "$CC_FLOATING_IP_ID" -f value -c floating_ip_address )

echo Associating floating ip with instance.
openstack server add floating ip "$INSTANCE_NAME" "$CC_PUBLIC_IP" 
echo "Wait for instance to start"
sleep 90

## Create lamp.pp and puppet installation script##

cat << EOF > /tmp/puppetinstall.sh
wget https://apt.puppetlabs.com/puppetlabs-release-pc1-xenial.deb
sudo dpkg -i puppetlabs-release-pc1-xenial.deb
sudo apt -y update
sudo apt -y upgrade
sudo apt -y install puppet-agent
echo 'PATH="$PATH:/opt/puppetlabs/puppet/bin"' >> /home/ubuntu/.profile
sudo sed -i 's/Defaults\s*secure/#Defaults\tsecure/' /etc/sudoers
sudo systemctl stop puppet.service; sudo systemctl disable puppet.service
exit
EOF

cat << EOF > /tmp/lamp.pp
# execute 'apt-get update'

exec { 'apt-update':                    # exec resource named 'apt-update'
  command => '/usr/bin/apt-get update'  # command this resource will run
}



# install apache2 package

package { 'apache2':
  require => Exec['apt-update'],        # require 'apt-update' before installing
  ensure => installed,
}

# ensure apache2 service is running

service { 'apache2':
  require => Package['apache2'],
  ensure => running,
}


# install mysql-server package

package { 'mysql-server':
  require => Exec['apt-update'],        # require 'apt-update' before installing
  ensure => installed,
}

# ensure mysql service is running

service { 'mysql':
  require => Package['mysql-server'],
  ensure => running,
}


# install php7 package

package { 'php7.0':
  require => Exec['apt-update'],        # require 'apt-update' before installing
  ensure => installed,
}

package { 'libapache2-mod-php':
  require => Package['php7.0'],        # require php7 before install
  ensure => installed,
}
# ensure info.php file exists

file { '/var/www/html/index.php':
  ensure => file,
  content => '<?php  phpinfo(); ?>',    # phpinfo code
  require => Package['apache2'],        # require 'apache2' package before creating
}

# ensure index.php is displayed

file { '/var/www/html/index.html':
  ensure => missing,
  require => Package['apache2'],        # require 'apache2' package before cr$
}
EOF

ssh -i ~/.ssh/id_rsa.pub ubuntu@$CC_PUBLIC_IP 'bash -s' < /tmp/puppetinstall.sh
scp -i ~/.ssh/id_rsa.pub '/tmp/lamp.pp' ubuntu@$CC_PUBLIC_IP:~
ssh -i ~/.ssh/id_rsa.pub ubuntu@$CC_PUBLIC_IP "echo 'sudo /opt/puppetlabs/bin/puppet apply lamp.pp' | sudo bash"
