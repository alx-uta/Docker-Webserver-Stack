#!/bin/bash
set -e

# Bash script to scaffold a new WordPress app with Docker support in /websites

# 1. Ask for domain and project name
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
BASE_DIR="$(pwd)"
WEBSITES_DIR="$(dirname "$(dirname "$BASE_DIR")")/websites"
SITE_DIR="$WEBSITES_DIR/$DOMAIN"
APP_DIR="$SITE_DIR/html"
DOCKER_DIR="$SITE_DIR/docker"

# 3. Create directories
mkdir -p "$APP_DIR"
mkdir -p "$DOCKER_DIR"

# 4. Copy Docker Compose and .env template from wordpress_app
cp "$BASE_DIR/wordpress_app/wordpress-compose.yml" "$DOCKER_DIR/wordpress-compose.yml"
cp "$BASE_DIR/wordpress_app/.env.example" "$DOCKER_DIR/.env"
cp "$BASE_DIR/wordpress_app/.gitignore" "$SITE_DIR/.gitignore" 2>/dev/null || true

# 5. Replace placeholders in copied files
sed -i "s/PROJECT_NAME/$PROJECT/g" "$DOCKER_DIR/wordpress-compose.yml"
sed -i "s/WEBSITE_DOMAIN/$DOMAIN/g" "$DOCKER_DIR/.env"
sed -i "s/PROJECT_NAME/$PROJECT/g" "$DOCKER_DIR/.env"

echo "WordPress app setup complete!"
echo "App directory: $APP_DIR"
echo "Docker config: $DOCKER_DIR"
echo "Remember to update your .env with real DB info and secrets."
