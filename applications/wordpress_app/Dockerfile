FROM wordpress:php8.1-apache

# Enable OPcache for better PHP performance
RUN docker-php-ext-configure opcache --enable-opcache \
    && docker-php-ext-install opcache

# Copy custom PHP configuration
COPY php.ini /usr/local/etc/php/conf.d/wordpress.ini

# Install Git, Subversion, and enable APCu for object caching
RUN apt-get update && \
    apt-get install -y git subversion mariadb-client wget gh && \
    pecl install apcu && \
    docker-php-ext-enable apcu && \
    rm -rf /var/lib/apt/lists/*

# Copy SSH keys and config for local development
# COPY ssh/id_rsa /root/.ssh/id_rsa
# COPY ssh/id_rsa.pub /root/.ssh/id_rsa.pub

# RUN chmod 600 /root/.ssh/id_rsa && \
#     chmod 644 /root/.ssh/id_rsa.pub

# Install WP-CLI
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php \
    && mv composer.phar /usr/local/bin/composer

