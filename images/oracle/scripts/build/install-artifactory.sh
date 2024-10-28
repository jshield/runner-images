#!/bin/bash

# Upgrade version for every release
ARTIFACTORY_VERSION=7.90.15

dnf -y upgrade

#Generate Self-Signed Cert
mkdir -p /etc/pki/tls/private/ /etc/pki/tls/certs/
openssl req -nodes -x509 -newkey rsa:4096 -keyout /etc/pki/tls/private/example.key -out /etc/pki/tls/certs/example.pem -days 356 -subj "/C=AU/ST=ACT/L=Canberra/O=IT/CN=*.localhost"

# install the Artifactory PRO and Nginx
curl -g -L -O "https://releases.jfrog.io/artifactory/artifactory-pro-rpms/jfrog-artifactory-pro/jfrog-artifactory-pro-${ARTIFACTORY_VERSION}.rpm"
dnf install -y nginx | sudo tee -a /tmp/install-nginx.log 2>&1
yum install -y jfrog-artifactory-pro-${ARTIFACTORY_VERSION}.rpm | sudo tee /tmp/install-artifactory.log 2>&1

# Add callhome metadata (allow us to collect information)
mkdir -p /var/opt/jfrog/artifactory/etc/info
cat <<EOF >/var/opt/jfrog/artifactory/etc/info/installer-info.json
{
  "productId": "ARM_artifactory-pro-vm/1.0.0",
  "features": [
    {
      "featureId": "Partner/ACC-007221"
    }
  ]
}
EOF

#Install database drivers (for Java 11, path is different for RT6 and RT7)
curl --retry 5 -L -o /opt/jfrog/artifactory/app/artifactory/tomcat/lib/mysql-connector-java-5.1.38.jar https://repo1.maven.org/maven2/mysql/mysql-connector-java/5.1.38/mysql-connector-java-5.1.38.jar >> /tmp/install-databse-driver.log 2>&1
curl --retry 5 -L -o /opt/jfrog/artifactory/app/artifactory/tomcat/lib/mssql-jdbc-7.4.1.jre11.jar https://repo1.maven.org/maven2/com/microsoft/sqlserver/mssql-jdbc/7.4.1.jre11/mssql-jdbc-7.4.1.jre11.jar >> /tmp/install-databse-driver.log 2>&1
curl --retry 5 -L -o /opt/jfrog/artifactory/app/artifactory/tomcat/lib/postgresql-42.2.18.jar https://jdbc.postgresql.org/download/postgresql-42.2.18.jar >> /tmp/install-databse-driver.log 2>&1

#Configuring nginx
rm /etc/nginx/sites-enabled/default

printf "\nartifactory.ping.allowUnauthenticated=true" >> /var/opt/jfrog/artifactory/etc/artifactory/artifactory.system.properties

chown artifactory:artifactory -R /var/opt/jfrog/artifactory/* && chown artifactory:artifactory -R /var/opt/jfrog/artifactory/etc/*

# Remove Artifactory service from boot up run
systemctl disable artifactory
systemctl disable nginx
