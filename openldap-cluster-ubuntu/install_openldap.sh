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
let "index+=1" # index is 0-based, but we want 1-based

# install debconf
apt-get -y update
apt-get install debconf

echo "===== Set up siltent install of slapd ====="
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

echo "===== Install slapd ====="
apt-get -y install slapd ldap-utils

echo "===== Install phpldapadmin ====="
# install phpldapadmin
sudo apt-get -y install phpldapadmin

echo "===== Configure phpldapadmin ====="
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

echo "===== Set up master-master replication ====="

echo "===== Install ntp package ====="
apt-get -y install ntp
/etc/init.d/ntp restart

echo "===== Create entries in hosts file ====="
for i in `seq 1 $vmCount`; do
    let "j=i-1"
    echo "$privateIPAddressPrefix$j ldap$i.$subdomain.local ldap$i" >> /etc/hosts
done

echo "===== Modify slapd default configuration ====="
sed -i "s/SLAPD_SERVICES=\"ldap:\/\/\/ ldapi:\/\/\/\"/SLAPD_SERVICES=\"ldapi:\/\/\/ ldap:\/\/ldap$index.$subdomain.local\/\"/" /etc/default/slapd

echo "===== Generate password ====="
SLAPPASSWD=$(slappasswd -s $adminpass)

echo "===== Load syncProv module ====="
ldapmodify -Y EXTERNAL -H ldapi:/// -f config_1_loadSyncProvModule.ldif

echo "===== Set server ID ====="
sed -i "s/{serverID}/$index/" config_2_setServerID.ldif
ldapmodify -Y EXTERNAL -H ldapi:/// -f config_2_setServerID.ldif

echo "===== Set password ====="
sed -i "s@{password}@$SLAPPASSWD@" config_3_setConfigPW.ldif
ldapmodify -Y EXTERNAL -H ldapi:/// -f config_3_setConfigPW.ldif

echo "===== Add Root DN ====="
ldapmodify -Y EXTERNAL -H ldapi:/// -f config_3a_addOlcRootDN.ldif

echo "===== Add configuration replication ====="
for i in `seq 1 $vmCount`; do
    echo "olcServerID: $i ldap://ldap$i.$subdomain.local" >> config_4_addConfigReplication.ldif
done

ldapmodify -Y EXTERNAL -H ldapi:/// -f config_4_addConfigReplication.ldif

echo "===== Add syncProv to the configuration ====="
ldapmodify -Y EXTERNAL -H ldapi:/// -f config_5_addSyncProv.ldif

echo "===== Add syncRepl among servers ====="
syncRepl=""
for i in `seq 1 $vmCount`; do
    syncRepl=$syncRepl"olcSyncRepl: rid=00$i provider=ldap://ldap$i.$subdomain.local binddn=\"cn=admin,cn=config\" bindmethod=simple credentials=secret searchbase=\"cn=config\" type=refreshAndPersist retry=\"5 5 300 5\" timeout=1\n"
done

sed -i "s@{syncRepl}@$syncRepl@" config_6_addSyncRepl.ldif
ldapmodify -Y EXTERNAL -H ldapi:/// -f config_6_addSyncRepl.ldif

# test replication
# ldapmodify -Y EXTERNAL -H ldapi:/// -f config_7_testConfigReplication.ldif

# Since configuration is expected to be replicating at this point, we only need to do this on the first server.
if [ "$index" = "1" ]; then

    echo "===== Modify HDB config ====="

    echo "===== Add syncProv to HDB ====="
    ldapmodify -Y EXTERNAL -H ldapi:/// -f hdb_1_addSyncProvToHDB.ldif

    echo "===== Add suffix ====="
    sed -i "s@{dn}@dc=$subdomain,dc=$location,dc=cloudapp,dc=azure,dc=com@" hdb_2_addOlcSuffix.ldif
    ldapmodify -Y EXTERNAL -H ldapi:/// -f hdb_2_addOlcSuffix.ldif

    echo "===== Add Root DN ====="
    sed -i "s@{dn}@dc=$subdomain,dc=$location,dc=cloudapp,dc=azure,dc=com@" hdb_3_addOlcRootDN.ldif
    ldapmodify -Y EXTERNAL -H ldapi:/// -f hdb_3_addOlcRootDN.ldif

    echo "===== Add Root password ====="
    sed -i "s@{password}@$SLAPPASSWD@" hdb_4_addOlcRootPW.ldif
    ldapmodify -Y EXTERNAL -H ldapi:/// -f hdb_4_addOlcRootPW.ldif

    echo "===== Add  syncRepl among servers ====="
    for i in `seq 1 $vmCount`; do
        let "rid=i+vmCount"
        echo "olcSyncRepl: rid=10$rid provider=ldap://ldap$i.$subdomain.local binddn=\"cn=admin,dc=$subdomain,dc=$location,dc=cloudapp,dc=azure,dc=com\" bindmethod=simple credentials=secret searchbase=\"dc=$subdomain,dc=$location,dc=cloudapp,dc=azure,dc=com\" type=refreshAndPersist interval=00:00:00:10 retry=\"5 5 300 5\" timeout=1" >> hdb_5_addOlcSyncRepl.ldif
    done

    ldapmodify -Y EXTERNAL -H ldapi:/// -f hdb_5_addOlcSyncRepl.ldif

    echo "===== Add mirror mode ====="
    ldapmodify -Y EXTERNAL -H ldapi:/// -f hdb_6_addOlcMirrorMode.ldif

    echo "===== Add index to the database ====="
    ldapmodify -Y EXTERNAL -H ldapi:/// -f hdb_7_addIndexHDB.ldif

fi

echo "===== Restart Apache ====="
apachectl restart
