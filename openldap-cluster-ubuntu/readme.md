# Deploy OpenLDAP cluster on Ubuntu.

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fvinhub%2Fazure-quickstart-templates%2Foldap2%2Fopenldap-cluster-ubuntu%2Fazuredeploy.json" target="_blank"><img src="http://azuredeploy.net/deploybutton.png"/></a>

This template deploys an OpenLDAP cluster on Ubuntu. It creates multiple Ubuntu VMs (up to 5, but can be easily increased) and does a silent install of OpenLDAP on them. Then it sets up N-way multi-master replication on them. After the deployment is successful, you can go to /phpldapadmin to start congfiguring OpenLDAP.
