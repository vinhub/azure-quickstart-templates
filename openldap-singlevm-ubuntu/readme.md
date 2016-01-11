# Deploy OpenLDAP on Ubuntu on a single VM.

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fvinhub%2Fazure-quickstart-templates%2Foldap4%2Fopenldap-singlevm-ubuntu%2Fazuredeploy.json" target="_blank"><img src="http://azuredeploy.net/deploybutton.png"/></a>

This template deploys OpenLDAP on Ubuntu. It creates a single Ubuntu VM and does a silent install of OpenLDAP on it. It also installs TLS support and PhpLDAPAdmin. After the deployment is successful, you can go to /phpldapadmin to start working with OpenLDAP or access it directly from the LDAP endpoint.
