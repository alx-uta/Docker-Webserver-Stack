#!/bin/bash
set -e

# Bash script to scaffold a new PHP app with Docker support in /websites

# 1. Ask for domain and PHP project name
read -p "Enter the domain name (e.g., site1_com): " DOMAIN
read -p "Enter the PHP project name (e.g., myapp): " PROJECT

# Validate project name (must be at least 2 characters and Docker-friendly)
if [ ${#PROJECT} -lt 2 ]; then
    echo "Error: Project name must be at least 2 characters long"
    exit 1
fi

# Ensure project name is Docker-friendly (only alphanumeric, hyphens, underscores)
if ! echo "$PROJECT" | grep -q '^[a-zA-Z0-9][a-zA-Z0-9_.-]*$'; then
    echo "Error: Project name must start with alphanumeric character and contain only letters, numbers, hyphens, dots, and underscores"
    exit 1
fi

# 2. Set up paths
BASE_DIR="$(pwd)"
WEBSITES_DIR="$(dirname "$(dirname "$BASE_DIR")")/websites"
SITE_DIR="$WEBSITES_DIR/$DOMAIN"
APP_DIR="$SITE_DIR/html"
DOCKER_DIR="$SITE_DIR/docker"

# 3. Create directories
mkdir -p "$APP_DIR"
mkdir -p "$APP_DIR/src"
mkdir -p "$APP_DIR/public"
mkdir -p "$APP_DIR/config"
mkdir -p "$APP_DIR/tests"
mkdir -p "$DOCKER_DIR"

# 4. Create a basic index.php file
cat > "$APP_DIR/index.php" <<EOF
<?php
// Basic PHP application for $PROJECT
// Domain: $DOMAIN

// Configuration
\$siteName = '$PROJECT';
\$domain = '$DOMAIN';

// Database configuration (if needed)
\$dbHost = getenv('DB_HOST') ?: 'localhost';
\$dbUser = getenv('DB_USER') ?: 'root';
\$dbPass = getenv('DB_PASSWORD') ?: '';
\$dbName = getenv('DB_NAME') ?: '$PROJECT';

?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo htmlspecialchars(\$siteName); ?></title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            background: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            border-bottom: 2px solid #007cba;
            padding-bottom: 10px;
        }
        .info {
            background: #e7f3ff;
            padding: 15px;
            border-left: 4px solid #007cba;
            margin: 20px 0;
        }
        .success {
            background: #d4edda;
            padding: 15px;
            border-left: 4px solid #28a745;
            margin: 20px 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Welcome to <?php echo htmlspecialchars(\$siteName); ?></h1>
        
        <div class="success">
            <strong>Success!</strong> Your PHP application is running.
        </div>
        
        <div class="info">
            <h3>Application Information:</h3>
            <ul>
                <li><strong>Project Name:</strong> <?php echo htmlspecialchars(\$siteName); ?></li>
                <li><strong>Domain:</strong> <?php echo htmlspecialchars(\$domain); ?></li>
                <li><strong>PHP Version:</strong> <?php echo PHP_VERSION; ?></li>
                <li><strong>Server Software:</strong> <?php echo \$_SERVER['SERVER_SOFTWARE'] ?? 'Unknown'; ?></li>
                <li><strong>Document Root:</strong> <?php echo \$_SERVER['DOCUMENT_ROOT'] ?? 'Unknown'; ?></li>
            </ul>
        </div>

        <div class="info">
            <h3>Database Configuration:</h3>
            <ul>
                <li><strong>Host:</strong> <?php echo htmlspecialchars(\$dbHost); ?></li>
                <li><strong>User:</strong> <?php echo htmlspecialchars(\$dbUser); ?></li>
                <li><strong>Database:</strong> <?php echo htmlspecialchars(\$dbName); ?></li>
                <li><strong>Connection Status:</strong> 
                    <?php
                    try {
                        if (\$dbHost !== 'localhost' && !empty(\$dbUser)) {
                            \$pdo = new PDO("mysql:host=\$dbHost;dbname=\$dbName", \$dbUser, \$dbPass);
                            echo '<span style="color: green;">✓ Connected</span>';
                        } else {
                            echo '<span style="color: orange;">⚠ Not configured</span>';
                        }
                    } catch (Exception \$e) {
                        echo '<span style="color: red;">✗ Connection failed</span>';
                    }
                    ?>
                </li>
            </ul>
        </div>

        <div class="info">
            <h3>PHP Extensions:</h3>
            <p>
                <?php
                \$extensions = ['pdo', 'pdo_mysql', 'mysqli', 'gd', 'zip', 'opcache', 'json'];
                foreach (\$extensions as \$ext) {
                    \$status = extension_loaded(\$ext) ? '✓' : '✗';
                    \$color = extension_loaded(\$ext) ? 'green' : 'red';
                    echo "<span style='color: \$color;'>\$status \$ext</span> ";
                }
                ?>
            </p>
        </div>

        <div class="info">
            <h3>Next Steps:</h3>
            <ul>
                <li>Edit <code>/html/index.php</code> to customize your application</li>
                <li>Add your PHP files to the <code>/html</code> directory</li>
                <li>Configure database settings in <code>/docker/.env</code></li>
                <li>Use <code>../applications/app_manage.sh</code> to manage this application</li>
            </ul>
        </div>
    </div>
</body>
</html>
EOF

# 5. Create a basic .htaccess file for Apache
cat > "$APP_DIR/.htaccess" <<EOF
# Basic .htaccess for PHP application
RewriteEngine On

# Security headers
Header always set X-Content-Type-Options nosniff
Header always set X-Frame-Options DENY
Header always set X-XSS-Protection "1; mode=block"
Header always set Referrer-Policy "strict-origin-when-cross-origin"

# Hide sensitive files
<Files ".env">
    Order allow,deny
    Deny from all
</Files>

<Files "*.ini">
    Order allow,deny
    Deny from all
</Files>

# Pretty URLs (uncomment if needed)
# RewriteCond %{REQUEST_FILENAME} !-f
# RewriteCond %{REQUEST_FILENAME} !-d
# RewriteRule ^(.*)$ index.php?route=\$1 [QSA,L]

# Cache static files
<IfModule mod_expires.c>
    ExpiresActive On
    ExpiresByType text/css "access plus 1 month"
    ExpiresByType application/javascript "access plus 1 month"
    ExpiresByType image/png "access plus 1 month"
    ExpiresByType image/jpg "access plus 1 month"
    ExpiresByType image/jpeg "access plus 1 month"
    ExpiresByType image/gif "access plus 1 month"
</IfModule>
EOF

# 6. Copy Docker Compose, .env.example, php.ini, composer.json, config, README, and .gitignore
cp "$BASE_DIR/php_app/php-compose.yml" "$DOCKER_DIR/php-compose.yml"
cp "$BASE_DIR/php_app/.env.example" "$DOCKER_DIR/.env"
cp "$BASE_DIR/php_app/php.ini.example" "$DOCKER_DIR/php.ini"
cp "$BASE_DIR/php_app/composer.json.example" "$APP_DIR/composer.json"
cp "$BASE_DIR/php_app/config.php.example" "$APP_DIR/config/config.php"
cp "$BASE_DIR/php_app/README.md.example" "$SITE_DIR/README.md"
cp "$BASE_DIR/php_app/.gitignore" "$SITE_DIR/.gitignore"

# 7. Replace placeholders in copied files
sed -i "s/PROJECT_NAME/$PROJECT/g" "$DOCKER_DIR/php-compose.yml"
sed -i "s/WEBSITE_DOMAIN/$DOMAIN/g" "$DOCKER_DIR/.env"
sed -i "s/PROJECT_NAME/$PROJECT/g" "$DOCKER_DIR/.env"
sed -i "s/WEBSITE_DB_NAME/${PROJECT}_db/g" "$DOCKER_DIR/.env"
sed -i "s/MYSQL_DB_USER/mysql_user/g" "$DOCKER_DIR/.env"
sed -i "s/MYSQL_DB_PASSWORD/mysql_password/g" "$DOCKER_DIR/.env"

# Replace placeholders in composer.json
sed -i "s/PROJECT_NAME/$PROJECT/g" "$APP_DIR/composer.json"
sed -i "s/WEBSITE_DOMAIN/$DOMAIN/g" "$APP_DIR/composer.json"

# Replace placeholders in README.md
sed -i "s/PROJECT_NAME/$PROJECT/g" "$SITE_DIR/README.md"
sed -i "s/WEBSITE_DOMAIN/$DOMAIN/g" "$SITE_DIR/README.md"

# Replace placeholders in config.php
sed -i "s/PROJECT_NAME/$PROJECT/g" "$APP_DIR/config/config.php"
sed -i "s/WEBSITE_DOMAIN/$DOMAIN/g" "$APP_DIR/config/config.php"

# 8. Update container name in php-compose.yml (container name is already set correctly by template replacement)

echo "PHP app setup complete!"
echo "========================================"
echo "✓ App directory: $APP_DIR"
echo "✓ Docker config: $DOCKER_DIR"
echo "✓ Default page created at: $APP_DIR/index.php"
echo "✓ Configuration file: $APP_DIR/config/config.php"
echo "✓ Composer.json created: $APP_DIR/composer.json"
echo "✓ README.md created: $SITE_DIR/README.md"
echo ""
echo "Next steps:"
echo "1. Update database credentials in $DOCKER_DIR/.env"
echo "2. Start the application:"
echo "   cd $DOCKER_DIR"
echo "   docker-compose -p $PROJECT -f php-compose.yml up -d"
echo "3. Or use the application manager:"
echo "   cd ../applications && ./app_manage.sh"
echo ""
echo "Your PHP application will be available at http://localhost"
echo "(Configure your reverse proxy to point to the container)"
