#!/bin/bash

cd /var/www/MISP/app/Config
#chown -R www-data:www-data /var/www/MISP
#chmod -R 750 /var/www/MISP
sed -i "s/db\s*login/misp/" database.php
sed -i "s/localhost/$MARIADB_HOSTNAME/" database.php
sed -i "s/3306/$MARIADB_PORT/" database.php
sed -i "s/db\s*password/$MARIADB_PASSWORD/" database.php
#sed -i "s&\(database'.*'\)\([^']*\)'&\1\2$MARIADB_USER'&g" database.php
## Set database salt
sed -i "s&\('salt'\)\(.*\)\(=>\)\(.*\)\(',\)&\1 \3 'CHANGEMECHANGEMEMISP\5&g" config.php
## Limits php incremented
sed -i 's/\(max_execution_time = \)[0-9]\+/\1350/g' /etc/php5/apache2/php.ini
sed -i 's/\(memory_limit = \)[0-9]\+/\1512/g' /etc/php5/apache2/php.ini

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

#chown -R www-data:www-data /var/www/MISP
/usr/bin/supervisord
