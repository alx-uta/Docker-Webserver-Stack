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

# 3. Create directories
mkdir -p "$APP_DIR"
mkdir -p "$DOCKER_DIR"

# 4. Check if template files exist
if [ ! -f "$BASE_DIR/wordpress_app/wordpress-compose.yml" ]; then
    echo "Error: WordPress template files not found in $BASE_DIR/wordpress_app/"
    echo "Please ensure the wordpress_app directory exists with the required template files."
    exit 1
fi

# 5. Copy Docker Compose and .env template from wordpress_app
cp "$BASE_DIR/wordpress_app/wordpress-compose.yml" "$DOCKER_DIR/wordpress-compose.yml"
cp "$BASE_DIR/wordpress_app/.env.example" "$DOCKER_DIR/.env"
cp "$BASE_DIR/wordpress_app/.gitignore" "$SITE_DIR/.gitignore" 2>/dev/null || true

# 6. Replace placeholders in copied files
sed -i "s/PROJECT_NAME/$PROJECT/g" "$DOCKER_DIR/wordpress-compose.yml"
sed -i "s/WEBSITE_DOMAIN/$DOMAIN/g" "$DOCKER_DIR/.env"
sed -i "s/PROJECT_NAME/$PROJECT/g" "$DOCKER_DIR/.env"

echo "WordPress app setup complete!"
echo "App directory: $APP_DIR"
echo "Docker config: $DOCKER_DIR"
echo "Remember to update your .env with real DB info and secrets."
echo ""
echo "Next steps:"
echo "1. Edit $DOCKER_DIR/.env with your database credentials"
echo "2. Use the application manager to start your WordPress site:"
echo "   cd $APPLICATIONS_DIR && ./app_manage.sh"
