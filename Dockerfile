FROM ubuntu:bionic
MAINTAINER OpenCyberSec - https://github.com/OpenCyberSec

ENV MISP_VERSION v2.4.105
ENV CybOX_VERSION v2.1.0.12
ENV PYTHONSTIX_VERSION v1.1.1.4
ENV CAKERESQUE_VERSION 4.1.2

RUN apt-get update -q \
        && DEBIAN_FRONTEND=noninteractive apt-get install -qy --no-install-recommends apt-utils supervisor build-essential zip php-pear git redis-server make python-dev python-pip libxml2-dev libxslt1-dev zlib1g-dev php-dev libapache2-mod-php php-mysql curl apache2 mysql-client postfix python-dev python-pip libxml2-dev libxslt-dev zlib1g-dev gcc libsodium-dev \
        && pip install -U pip setuptools \
        && DEBIAN_FRONTEND=noninteractive apt-get install -qy --no-install-recommends php-redis pkg-config \
        && apt-get clean \
        && rm -rf /var/lib/apt/lists/*

RUN pear install Crypt_GPG

RUN cd /var/www \
        && git clone https://github.com/MISP/MISP.git /var/www/MISP \
        && cd /var/www/MISP \
        && git checkout tags/$MISP_VERSION \
        && cd /var/www/MISP \
        && git config core.filemode false

RUN cd /var/www/MISP/app/files/scripts \
        && git clone https://github.com/CybOXProject/python-cybox.git \
        && cd /var/www/MISP/app/files/scripts/python-cybox \
        && git checkout $CybOX_VERSION \
        && python setup.py install
RUN cd /var/www/MISP/app/files/scripts \
        && git clone https://github.com/STIXProject/python-stix.git \
        && cd /var/www/MISP/app/files/scripts/python-stix \
        && git checkout $PYTHONSTIX_VERSION \
        && python setup.py install
RUN cd /var/www/MISP \
        && git submodule init \
        && git submodule update
RUN cd /var/www/MISP/app \
        && curl -s https://getcomposer.org/installer | php \
        && php composer.phar require kamisama/cake-resque:$CAKERESQUE_VERSION \
        && php composer.phar config vendor-dir Vendor \
        && php composer.phar install

RUN phpenmod redis

RUN cp -fa /var/www/MISP/INSTALL/setup/config.php /var/www/MISP/app/Plugin/CakeResque/Config/config.php

RUN chown -R www-data:www-data /var/www/MISP \
        && chmod -R 750 /var/www/MISP \
        && chmod -R g+ws /var/www/MISP/app/tmp \
        && chmod -R g+ws /var/www/MISP/app/files \
        && chmod -R g+ws /var/www/MISP/app/files/scripts/tmp

RUN cp /var/www/MISP/INSTALL/apache.24.misp.ssl /etc/apache2/sites-available/misp.conf
RUN a2dissite 000-default \
        && a2ensite misp

RUN cd /etc/apache2/sites-available/ && \
    sed -i "s&\(SSLCertificateChainFile.*\)&&g" misp.conf && \
    sed -i "s&\(VirtualHost \)\(.*\)\>&\1*:443&g" misp.conf && \
    a2enmod ssl

RUN a2enmod rewrite && \
    a2enmod headers

RUN cd /var/www/MISP/app/Config \
        && cp -a bootstrap.default.php bootstrap.php \
        && cp -a database.default.php database.php \
        && cp -a core.default.php core.php \
        && cp -a config.default.php config.php

RUN pip install redis \
    && cd /usr/local/src/ \
    && curl -L -O https://github.com/zeromq/zeromq4-1/releases/download/v4.1.6/zeromq-4.1.6.tar.gz \
    && tar -xvf zeromq-4.1.6.tar.gz \
    && cd zeromq-4.1.6/ \
    && ./autogen.sh \
    && ./configure \
    && make \
    && make install \
    && ldconfig \
    && pip install pyzmq

ADD conf/misp.conf /etc/supervisor/conf.d/misp.conf
ADD conf/nodaemon.conf /etc/supervisor/conf.d/nodaemon.conf
ADD scripts/start.sh /start.sh

RUN usermod --shell /bin/bash www-data
RUN cp /usr/share/zoneinfo/Europe/Madrid /etc/localtime

ENTRYPOINT ["/bin/bash","/start.sh"]
