#!/bin/bash

# parameters
adminpass=$1
subdomain=$2
location=$3
organization=$4

# variables
domain=$subdomain.$location.cloudapp.azure.com

# install debconf
apt-get -y update
apt-get install debconf

# silent install of slapd
export DEBIAN_FRONTEND=noninteractive
echo slapd slapd/password1 password $adminpass | debconf-set-selections
echo slapd slapd/password2 password $adminpass | debconf-set-selections
echo slapd slapd/allow_ldap_v2 boolean false | debconf-set-selections
echo slapd slapd/domain string $domain | debconf-set-selections
echo slapd slapd/no_configuration boolean false | debconf-set-selections
echo slapd slapd/move_old_database boolean true | debconf-set-selections
# echo slapd slapd/dump_database_destdir string /var/backups/slapd-VERSION | debconf-set-selections
echo slapd slapd/purge_database boolean false | debconf-set-selections
echo slapd shared/organization string $organization | debconf-set-selections
echo slapd slapd/backend select HDB | debconf-set-selections

apt-get -y install slapd ldap-utils

# install phpldapadmin
sudo apt-get -y install phpldapadmin

# backup existing config.php file for phpldapadmin and create a new one
cp /etc/phpldapadmin/config.php /etc/phpldapadmin/config.php.old
echo "<?php " > /etc/phpldapadmin/config.php
echo "\$servers = new Datastore();" >> /etc/phpldapadmin/config.php
echo "\$servers->newServer('ldap_pla');" >> /etc/phpldapadmin/config.php
echo "\$servers->setValue('server','name','$organization');" >> /etc/phpldapadmin/config.php
echo "\$servers->setValue('server','host','$domain');" >> /etc/phpldapadmin/config.php
echo "\$servers->setValue('server','base',array('dc=$subdomain,dc=$location,dc=cloudapp,dc=azure,dc=com'));" >> /etc/phpldapadmin/config.php
echo "\$servers->setValue('login','bind_id','cn=admin,dc=$subdomain,dc=$location,dc=cloudapp,dc=azure,dc=com');" >> /etc/phpldapadmin/config.php
echo "\$config->custom->appearance['hide_template_warning'] = true;" >> /etc/phpldapadmin/config.php
echo "?>" >> /etc/phpldapadmin/config.php

# backup existing /usr/share/phpldapadmin/lib/TemplateRender.php and change password_hash to password_hash_custom (to take care of template error)
cp /usr/share/phpldapadmin/lib/TemplateRender.php /usr/share/phpldapadmin/lib/TemplateRender.php.old
sed -i "s/password_hash/password_hash_custom/" /usr/share/phpldapadmin/lib/TemplateRender.php

# restart Apache
apachectl restart
