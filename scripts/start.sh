#!/bin/bash
# I'm using also as reference the misp-vagrant project - Thx @cedricbonhomme and @adulau
PATH_TO_MISP=/var/www/MISP

echo "- GENERAL: Starting async chown & chmods"
chown -R www-data:www-data $PATH_TO_MISP &
chown -R www-data:www-data /persist &
chmod -R 750 $PATH_TO_MISP/app/Config &

## Set database salt //TODO: put in ENV
echo "- GENERAL: Setting database SALT"
sed -i "s&\('salt'\)\(.*\)\(=>\)\(.*\)\(',\)&\1 \3 'CHANGEMECHANGEMEMISP\5&g" $PATH_TO_MISP/app/Config/config.php

echo "- PHP: Setting custom parameters in php.ini"
sed -i 's/\(max_execution_time = \)[0-9]\+/\1350/g' /etc/php/7.2/apache2/php.ini
sed -i 's/\(memory_limit = \)[0-9]\+/\1512/g' /etc/php/7.2/apache2/php.ini

echo "- GNUPG: Healthcheck"
if ! [ -d /persist/.gnupg ];then
	echo "- GNUPG doesn't exist, we will work in that"
	sudo -u www-data mkdir /persist/.gnupg
	chmod 700 /persist/.gnupg
	echo -ne "%echo Generating a default key\nKey-Type: default\nKey-Length: $GPG_KEY_LENGTH\nSubkey-Type: default\nName-Real: $GPG_REAL_NAME\nName-Comment: no comment\nName-Email: $GPG_EMAIL_ADDRESS\nExpire-Date: 0\nPassphrase: '$GPG_PASSPHRASE'\n# Do a commit here, so that we can later print "done"\n%commit\n%echo done\n" > gen-key-script
	sudo -u www-data gpg --homedir /persist/.gnupg --batch --gen-key gen-key-script
	res=$?
	rm gen-key-script
	if [[ "$res" == "0" ]];then
		echo "- GNUPG Created OK"
	else
		echo "- GNUPG ERROR"
	fi
else
	echo "- GNUPG OK"
fi

if ! [ -f $PATH_TO_MISP/app/webroot/gpg.asc ];then
	echo "- GNUPG Public key doesn't exist, we will work in that..."
	sudo -u www-data gpg --homedir /persist/.gnupg --batch --gen-key gen-key-scriptgpg --homedir /persist/.gnupg --export --armor $EMAIL_ADDRESS > $PATH_TO_MISP/app/webroot/gpg.asc
	if [[ "$?" == "0" ]];then
		echo "- GNUPG Public key exported ok"
	else
		echo "- GNUPG Public key error"
	fi
fi

if ! [ -d $PATH_TO_MISP/.gnupg ];then
        ln -s /persist/.gnupg $PATH_TO_MISP/.gnupg
fi

sudo -u www-data cat > /var/www/MISP/app/Config/database.php <<EOF
<?php
class DATABASE_CONFIG {
        public \$default = array(
                'datasource' => 'Database/Mysql',
                'persistent' => false,
                'host' => '$MARIADB_HOSTNAME',
                'login' => '$MARIADB_USER',
                'port' => 3306, // MySQL & MariaDB
                'password' => '$MARIADB_PASSWORD',
                'database' => '$MARIADB_DATABASE',
                'prefix' => '',
                'encoding' => 'utf8',
        );
}
EOF

echo "- MYSQL: Let me check if the db is ready"
tm=0
while [[ $(echo lol > /dev/tcp/$MARIADB_HOSTNAME/3306 2>/dev/null >/dev/null;echo $?) != "0" && $tm -lt 10 ]];do
	echo "- MYSQL: Waiting for the mysql server be ready"
	sleep 5
	tm=$(($tm + 1))
done
if [[ $(echo lol > /dev/tcp/$MARIADB_HOSTNAME/3306 2>/dev/null >/dev/null;echo $?) != "0" ]];then
	echo "- MYSQL: ERROR - Can't connect to mysql server"
	exit 1
fi
# TODO: Do something better with that
echo "Connecting to database ..."
linescount=`echo 'show tables from misp;' | mysql $MARIADB_DATABASE -u misp --password=$MARIADB_PASSWORD -h $MARIADB_HOSTNAME -P $MARIADB_PORT 2>1 | awk 'END { print NR }'`
ret=`echo 'show tables from misp;' | mysql $MARIADB_DATABASE -u misp --password=$MARIADB_PASSWORD -h $MARIADB_HOSTNAME -P $MARIADB_PORT 2>1`
if [ $? -eq 0 ]; then
  echo "Connected to database successfully"
  [[ $ret == "" ]] && empty=1 || empty=0
  if [ $empty -eq 0 ]; then
    echo "Database misp$MARIADB_USER not empty, not updating contents"
  else
    echo "Database misp$MARIADB_USER empty, creating structure"
    echo "Importing /var/www/MISP/INSTALL/MYSQL.sql"
    ret=`mysql $MARIADB_DATABASE -u misp --password=$MARIADB_PASSWORD -h $MARIADB_HOSTNAME -P $MARIADB_PORT < /var/www/MISP/INSTALL/MYSQL.sql`
    if [ $? -eq 0 ]; then
        echo "Imported /var/www/MISP/INSTALL/MYSQL.sql successfully"
    else
        echo "ERROR: Importing /var/www/MISP/INSTALL/MYSQL.sql failed:"
        echo $ret
    fi
  fi
else
  echo "ERROR: Connecting to database failed:"
  echo $ret
fi

#SSL CONF
echo "- SSL: Healthchecks"
echo "- SSL: Checking if exist the SSL key"
if ! [ -f /persist/ssl/new.cert.key ];then
	echo "- SSL: SSL key doesn't exist... we will work on that"
	mkdir -p /persist/ssl/
	openssl req -nodes -newkey rsa:4096 -keyout /persist/ssl/new.cert.key -out /persist/ssl/new.cert.csr -subj "$APACHE_CERT_SUBJ" 
	openssl x509 -in /persist/ssl/new.cert.csr -out /persist/ssl/new.cert.cert -req -signkey /persist/ssl/new.cert.key -days 1825
	chown www-data:www-data -R /persist/ssl
else
	echo "- SSL: SSL key exists"
fi
echo "- SSL: Checking if exist /etc/ssl/private directory"
if ! [ -d /etc/ssl/private/ ];then
	echo "- SSL: doesn't exist... we will create"
	mkdir -p /etc/ssl/private
	chown www-data:www-data -R /etc/ssl
else
	echo "- SSL: exists..."
fi
echo "- SSL: Checking if the cert is in the runtime directory"
if ! [ -h /etc/ssl/private/misp.local.crt ];then
	echo "- SSL: it doesn't"
	ln -s /persist/ssl/new.cert.cert /etc/ssl/private/misp.local.crt
else
	echo "- SSL: it is!"
fi
echo "- SSL: Checking if the cert key is in the runtime directory"
if ! [ -h /etc/ssl/private/misp.local.key ];then
	echo "- SSL: it doesn't"
	ln -s /persist/ssl/new.cert.key /etc/ssl/private/misp.local.key
else
	echo "- SSL: it is!"
fi
#SSL CONF END

sed -i "s&\(ServerAdmin \)\(.*\)&\1$APACHE_SERVERADMIN &g" /etc/apache2/sites-available/misp.conf
# TODO: Set default redis config
#$PATH_TO_MISP/app/Console/cake redis_host $REDIS_HOSTNAME
#$PATH_TO_MISP/app/Console/cake redis_port $REDIS_PORT
#$PATH_TO_MISP/app/Console/cake redis_database 13
$PATH_TO_MISP/app/Console/cake Baseurl $MISP_BASEURL
$PATH_TO_MISP/app/Console/cake Live $MISP_LIVE
# TODO: Set default gnupg homedir
#$PATH_TO_MISP/app/Console/cake homedir /persist/.gnupg

#TIMEZONE CONF
if ! [[ $TIMEZONE == "" ]];then
	TIMEZONE=Europe/Madrid
fi
if ! [ -f /usr/share/zoneinfo/$TIMEZONE ];then
	TIMEZONE=Europe/Madrid
fi
rm -rf /etc/localtime
ln -s /usr/share/zoneinfo/$TIMEZONE /etc/localtime
#TIMEZONE CONF END

# CONFIGS
#TODO: Check changes of MISP version.
if ! [ -d /persist/config ];then
	mkdir /persist/config
fi
if ! [ -f /persist/config/bootstrap.php ];then
	cp $PATH_TO_MISP/app/Config/bootstrap.php /persist/config/bootstrap.php
fi
rm -rf $PATH_TO_MISP/app/Config/bootstrap.php
ln -s /persist/config/bootstrap.php $PATH_TO_MISP/app/Config/bootstrap.php

if ! [ -f /persist/config/database.php ];then
        cp $PATH_TO_MISP/app/Config/database.php /persist/config/database.php
fi
rm -rf $PATH_TO_MISP/app/Config/database.php
ln -s /persist/config/database.php $PATH_TO_MISP/app/Config/database.php
if ! [ -f /persist/config/core.php ];then
        cp $PATH_TO_MISP/app/Config/core.php /persist/config/core.php
fi
rm -rf $PATH_TO_MISP/app/Config/core.php
ln -s /persist/config/core.php $PATH_TO_MISP/app/Config/core.php
if ! [ -f /persist/config/config.php ];then
        cp $PATH_TO_MISP/app/Config/config.php /persist/config/config.php
fi
rm -rf $PATH_TO_MISP/app/Config/config.php
ln -s /persist/config/config.php $PATH_TO_MISP/app/Config/config.php
# CONFIGS END

sed -i "s/'host' => 'localhost',/'host' => '$REDIS_HOSTNAME',/g" $PATH_TO_MISP/app/Plugin/CakeResque/Config/config.php

echo "--- MISP is ready ---"
echo "Login and passwords for the MISP image are the following:"
echo "Web interface (default network settings): $MISP_BASEURL"
echo "MISP admin:  admin@admin.test/admin"

chown www-data.www-data -R /persist &
/usr/bin/supervisord
