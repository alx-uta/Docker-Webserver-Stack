#!/bin/bash
set -e

# Bash script to scaffold a new WordPress app with Docker support in /websites

# Get the script directory and ensure we're in the right place
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLICATIONS_DIR="$(dirname "$SCRIPT_DIR")"
BASE_DIR="$APPLICATIONS_DIR"

# 1. Ask for domain and WordPress project name
read -p "Enter the domain name (e.g., site1_com): " DOMAIN
read -p "Enter the WordPress project name (e.g., myblog): " PROJECT

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
WEBSITES_DIR="$(dirname "$(dirname "$BASE_DIR")")/websites"
SITE_DIR="$WEBSITES_DIR/$DOMAIN"
APP_DIR="$SITE_DIR/html"
DOCKER_DIR="$SITE_DIR/docker"
DOCKER_LOCAL_VOLUME="../html:/var/www/html"

# Ask for volume type
echo "How do you want to store WordPress files for project '$PROJECT' (domain: $DOMAIN)?"
echo "1) Mount local directory ($DOCKER_LOCAL_VOLUME:/var/www/html)"
echo "2) Use Docker named volume (${PROJECT}_wordpress-html:/var/www/html)"
read -p "Choose 1 or 2 [1]: " VOLUME_CHOICE
VOLUME_CHOICE=${VOLUME_CHOICE:-1}

if [ "$VOLUME_CHOICE" = "2" ]; then
    DEFAULT_VOLUME_LOCATION="${PROJECT}_wordpress-html:/var/www/html"
    VOLUME_MODE="named"
else
    DEFAULT_VOLUME_LOCATION="$DOCKER_LOCAL_VOLUME"
    VOLUME_MODE="local"
fi

# 3. Create directories
mkdir -p "$APP_DIR"
mkdir -p "$DOCKER_DIR"

# 4. Check if template files exist
if [ ! -f "$BASE_DIR/wordpress_app/wordpress-compose.yml" ]; then
    echo "Error: WordPress template files not found in $BASE_DIR/wordpress_app/"
    echo "Please ensure the wordpress_app directory exists with the required template files."
    exit 1
fi

# 5. Copy Docker Compose, Dockerfile, php.ini and .env template from wordpress_app
cp "$BASE_DIR/wordpress_app/wordpress-compose.yml" "$DOCKER_DIR/wordpress-compose.yml"
cp "$BASE_DIR/wordpress_app/Dockerfile" "$DOCKER_DIR/Dockerfile"
cp "$BASE_DIR/wordpress_app/php.ini" "$DOCKER_DIR/php.ini"
cp "$BASE_DIR/wordpress_app/.env.example" "$DOCKER_DIR/.env"
cp "$BASE_DIR/wordpress_app/.gitignore" "$SITE_DIR/.gitignore" 2>/dev/null || true

# 6. Replace placeholders in copied files

# 6. Replace placeholders in copied files
sed -i "s/PROJECT_NAME/$PROJECT/g" "$DOCKER_DIR/wordpress-compose.yml"
sed -i "s/WEBSITE_DOMAIN/$DOMAIN/g" "$DOCKER_DIR/.env"
sed -i "s/PROJECT_NAME/$PROJECT/g" "$DOCKER_DIR/.env"
sed -i "s|DEFAULT_VOLUME_LOCATION|$DEFAULT_VOLUME_LOCATION|g" "$DOCKER_DIR/wordpress-compose.yml"

# 7. If using named volume, ensure volumes section is present and uncommented
if [ "$VOLUME_MODE" = "named" ]; then
    # Uncomment volumes section if commented, or append if missing
    if grep -q "^# volumes:" "$DOCKER_DIR/wordpress-compose.yml"; then
        sed -i "/^# volumes:/s/^# //" "$DOCKER_DIR/wordpress-compose.yml"
        sed -i "/^#   ${PROJECT}_wordpress-html:/s/^# //" "$DOCKER_DIR/wordpress-compose.yml"
    elif ! grep -q "volumes:" "$DOCKER_DIR/wordpress-compose.yml"; then
        echo -e "\nvolumes:\n  ${PROJECT}_wordpress-html:" >> "$DOCKER_DIR/wordpress-compose.yml"
    fi
fi

echo "WordPress app setup complete!"
echo "App directory: $APP_DIR"
echo "Docker config: $DOCKER_DIR"
echo "Remember to update your .env with real DB info and secrets."
echo ""
echo "Next steps:"
echo "1. Edit $DOCKER_DIR/.env with your database credentials"
echo "2. Use the application manager to start your WordPress site:"
echo "   cd $APPLICATIONS_DIR && ./app_manage.sh"
