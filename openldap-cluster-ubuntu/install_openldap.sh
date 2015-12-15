#!/bin/bash

# parameters
adminpass=$1
subdomain=$2
location=$3
organization=$4
privateIPAddressPrefix=$5
vmCount=$6
index=$7

# variables
domain=$subdomain.$location.cloudapp.azure.com
let index=index+1 # index is 0-based, but we want 1-based

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

# set up replication

# install ntp package
apt-get -y install ntp
/etc/init.d/ntp restart

# create entries in hosts file
for i in `seq 1 $vmCount`; do
    let j=i-1
    echo "$privateIPAddressPrefix$j ldap$i.local ldap$i" >> /etc/hosts
done

# modify slapd default configuration
sed -i "s/SLAPD_SERVICES=\"ldap:\/\/\/ ldapi:\/\/\/\"/SLAPD_SERVICES=\"ldapi:\/\/\/ ldap:\/\/ldap$index.local\/\"/" /etc/default/slapd

# generate password
SLAPPASSWD=$(slappasswd -s $adminpass)

# load syncProv module
ldapmodify -Y EXTERNAL -H ldapi:/// -f config_1_loadSyncProvModule.ldif

# set server ID
sed -i "s/{serverID}/$index/" config_2_setServerID.ldif
ldapmodify -Y EXTERNAL -H ldapi:/// -f config_2_setServerID.ldif

# set password
sed -i "s/{password}/$SLAPPASSWD/" config_3_setConfigPW.ldif
ldapmodify -Y EXTERNAL -H ldapi:/// -f config_3_setConfigPW.ldif

# add Root DN
ldapmodify -Y EXTERNAL -H ldapi:/// -f config_3a_addOlcRootDN.ldif

# add configuration replication
for i in `seq 1 $vmCount`; do
    echo "olcServerID: $i ldap://ldap$i.local" >> config_4_addConfigReplication.ldif
done

ldapmodify -Y EXTERNAL -H ldapi:/// -f config_4_addConfigReplication.ldif

# add syncProv to the configuration
ldapmodify -Y EXTERNAL -H ldapi:/// -f config_5_addSyncProv.ldif

# add syncRepl among servers
syncRepl=""
for i in `seq 1 $vmCount`; do
    syncRepl=$syncRepl"olcSyncRepl: rid=00$i provider=ldap://ldap$i.local binddn=\"cn=admin,cn=config\" bindmethod=simple credentials=secret searchbase=\"cn=config\" type=refreshAndPersist retry=\"5 5 300 5\" timeout=1\n"
done

sed -i "s@{syncRepl}@$syncRepl@" config_6_addSyncRepl.ldif
ldapmodify -Y EXTERNAL -H ldapi:/// -f config_6_addSyncRepl.ldif

# test replication
# ldapmodify -Y EXTERNAL -H ldapi:/// -f config_7_testConfigReplication.ldif

# modify HDB config

# add syncProv to HDB
ldapmodify -Y EXTERNAL -H ldapi:/// -f hdb_1_addSyncProvToHDB.ldif

# add suffix
ldapmodify -Y EXTERNAL -H ldapi:/// -f hdb_2_addOlcSuffix.ldif

# add Root DN
ldapmodify -Y EXTERNAL -H ldapi:/// -f hdb_3_addOlcRootDN.ldif

# add Root password
sed -i "s/{password}/$SLAPPASSWD/" hdb_4_addOlcRootPW.ldif
ldapmodify -Y EXTERNAL -H ldapi:/// -f hdb_4_addOlcRootPW.ldif

# add  syncRepl among servers
syncRepl=""
for i in `seq 1 $vmCount`; do
    syncRepl=$syncRepl"olcSyncRepl: rid=10$i provider=ldap://ldap$i.local binddn=\"cn=admin,dc=local\" bindmethod=simple credentials=secret searchbase=\"dc=local\" type=refreshAndPersist interval=00:00:00:10 retry=\"5 5 300 5\" timeout=1\n"
done

echo $syncRepl >> hdb_5_addOlcSyncRepl.ldif
ldapmodify -Y EXTERNAL -H ldapi:/// -f hdb_5_addOlcSyncRepl.ldif

# add mirror mode
ldapmodify -Y EXTERNAL -H ldapi:/// -f hdb_6_addOlcMirrorMode.ldif

# add index to the database
ldapmodify -Y EXTERNAL -H ldapi:/// -f hdb_7_addIndexHDB.ldif

# restart Apache
apachectl restart
