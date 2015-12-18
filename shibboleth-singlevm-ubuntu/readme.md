# Deploy Shibboleth Identity Provider on Ubuntu on a single VM.

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fvinhub%2Fazure-quickstart-templates%2Fmaster%2Fshibboleth-singlevm-ubuntu%2Fazuredeploy.json" target="_blank"><img src="http://azuredeploy.net/deploybutton.png"/></a>

This template deploys Shibboleth Identity Provider as a LAMP application on Ubuntu. It creates a single Ubuntu VM, does a silent install of MySQL, Apache, and Open JDK on it, and then deploys Shibboleth on it.  After the deployment is successful, you can go to /idp/profile/Status to check success.
