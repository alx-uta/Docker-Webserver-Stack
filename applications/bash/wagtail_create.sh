#!/bin/bash
set -e

# Bash script to scaffold a new Wagtail app with Docker support in /websites

# Get the script directory and ensure we're in the right place
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLICATIONS_DIR="$(dirname "$SCRIPT_DIR")"
BASE_DIR="$APPLICATIONS_DIR"

# 1. Ask for domain and Wagtail project name
read -p "Enter the domain name (e.g., site1_com): " DOMAIN
read -p "Enter the Wagtail project name (e.g., mysite): " PROJECT

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

# Ask if user wants a custom template
echo ""
echo "Would you like to use a custom Wagtail template?"
echo "1) Default Wagtail template"
echo "2) Custom template (provide URL)"
read -p "Select option (1 or 2, default: 1): " template_choice

TEMPLATE_ARG=""
if [ "$template_choice" = "2" ]; then
    read -p "Enter template URL (e.g., https://github.com/wagtail/news-template/archive/refs/heads/main.zip): " template_url
    if [ -n "$template_url" ]; then
        TEMPLATE_ARG="--template=$template_url"
    fi
fi

# 2. Set up paths
WEBSITES_DIR="$(dirname "$(dirname "$BASE_DIR")")/websites"
SITE_DIR="$WEBSITES_DIR/$DOMAIN"
APP_DIR="$SITE_DIR/app"
DOCKER_DIR="$SITE_DIR/docker"
DOCKER_LOCAL_VOLUME="../app:/app"

# Ask for volume type
echo ""
echo "How do you want to store Wagtail files for project '$PROJECT' (domain: $DOMAIN)?"
echo "1) Mount local directory (../app:/app)"
echo "2) Use Docker named volume (${PROJECT}_app_data:/app)"
read -p "Choose 1 or 2 [1]: " VOLUME_CHOICE
VOLUME_CHOICE=${VOLUME_CHOICE:-1}

if [ "$VOLUME_CHOICE" = "2" ]; then
    DEFAULT_VOLUME_LOCATION="${PROJECT}_app_data:/app"
    DEFAULT_STATIC_VOLUME="${PROJECT}_static_data:/app/static"
    DEFAULT_MEDIA_VOLUME="${PROJECT}_media_data:/app/media"
    VOLUME_MODE="named"
else
    DEFAULT_VOLUME_LOCATION="$DOCKER_LOCAL_VOLUME"
    DEFAULT_STATIC_VOLUME="../app/static:/app/static"
    DEFAULT_MEDIA_VOLUME="../app/media:/app/media"
    VOLUME_MODE="local"
fi

# 3. Create directories
mkdir -p "$APP_DIR/static" "$APP_DIR/media"
mkdir -p "$DOCKER_DIR"

# 4. Create and activate venv, install Wagtail
cd "$SITE_DIR"
python3 -m venv venv
source venv/bin/activate
cd "$APP_DIR"
echo "Installing pip and Wagtail (this may take a minute)..."
pip install --upgrade pip
pip install wagtail
echo "Wagtail installed successfully"

# 5. Start the new Wagtail project (this creates requirements.txt)
if [ -n "$TEMPLATE_ARG" ]; then
    wagtail start $TEMPLATE_ARG $PROJECT .
else
    wagtail start $PROJECT .
fi

# 5a. Install additional dependencies and update requirements.txt
pip install celery gunicorn redis python-dotenv watchdog flake8 isort black psycopg2-binary pillow whitenoise dj-database-url

# Update requirements.txt with all installed packages
pip freeze > requirements.txt

# 5b. Add celery.py for Celery integration
cat > "$APP_DIR/$PROJECT/celery.py" <<EOF
import os
from celery import Celery

os.environ.setdefault('DJANGO_SETTINGS_MODULE', '$PROJECT.settings.dev')

app = Celery('$PROJECT')
app.config_from_object('django.conf:settings', namespace='CELERY')
app.autodiscover_tasks()
EOF

# Update the __init__.py to import celery
if ! grep -q "from .celery import app as celery_app" "$APP_DIR/$PROJECT/__init__.py"; then
    echo -e "\nfrom .celery import app as celery_app\n\n__all__ = ('celery_app',)" >> "$APP_DIR/$PROJECT/__init__.py"
fi

# 5c. Add Celery configuration to base settings (Wagtail already creates settings directory)
if [ -f "$APP_DIR/$PROJECT/settings/base.py" ]; then
    cat >> "$APP_DIR/$PROJECT/settings/base.py" <<'EOF'

# Celery Configuration
CELERY_BROKER_URL = os.environ.get('CELERY_BROKER_URL', 'redis://redis:6379/0')
CELERY_RESULT_BACKEND = os.environ.get('CELERY_RESULT_BACKEND', 'redis://redis:6379/0')
CELERY_ACCEPT_CONTENT = ['application/json']
CELERY_TASK_SERIALIZER = 'json'
CELERY_RESULT_SERIALIZER = 'json'
CELERY_TIMEZONE = TIME_ZONE
EOF
fi

# 6. Check if template files exist
if [ ! -f "$BASE_DIR/wagtail_app/Dockerfile" ]; then
    echo "Error: Wagtail template files not found in $BASE_DIR/wagtail_app/"
    echo "Please ensure the wagtail_app directory exists with the required template files."
    exit 1
fi

# 7. Copy Dockerfile, .env.example, wagtail-compose.yml files, and .gitignore into /docker and /app
cp "$BASE_DIR/wagtail_app/Dockerfile" "$DOCKER_DIR/"
cp "$BASE_DIR/wagtail_app/.env.example" "$DOCKER_DIR/.env"
cp "$BASE_DIR/wagtail_app/wagtail-compose.yml" "$DOCKER_DIR/wagtail-compose.yml"
cp "$BASE_DIR/wagtail_app/wagtail-dev-compose.yml" "$DOCKER_DIR/wagtail-dev-compose.yml"
cp "$BASE_DIR/wagtail_app/wagtail-frontend-compose.yml" "$DOCKER_DIR/wagtail-frontend-compose.yml"
cp "$BASE_DIR/wagtail_app/.gitignore" "$SITE_DIR/.gitignore"

# Copy SSH keys to docker directory for build context
if [ -d "$BASE_DIR/ssh" ]; then
    cp -r "$BASE_DIR/ssh" "$DOCKER_DIR/"
    echo "SSH keys copied to $DOCKER_DIR/ssh"
else
    echo "Warning: SSH directory not found at $BASE_DIR/ssh"
fi

# Copy VSCode configuration to app/.vscode (only for local development)
if [ "$VOLUME_MODE" = "local" ] && [ -d "$BASE_DIR/wagtail_app/vscode.example" ]; then
    cp -r "$BASE_DIR/wagtail_app/vscode.example" "$APP_DIR/.vscode"
    echo "VSCode configuration copied to $APP_DIR/.vscode"
fi

# Function for cross-platform sed in-place editing
portable_sed() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# Generate a random SECRET_KEY
SECRET_KEY=$(python3 -c 'from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())')

# 8. Replace placeholders in all copied compose files
for compose_file in "wagtail-compose.yml" "wagtail-dev-compose.yml" "wagtail-frontend-compose.yml"; do
    portable_sed "s/PROJECT_NAME/$PROJECT/g" "$DOCKER_DIR/$compose_file"
    portable_sed "s/WEBSITE_DOMAIN/$DOMAIN/g" "$DOCKER_DIR/$compose_file"
    portable_sed "s/wagtail-PROJECT_NAME:latest/wagtail-$PROJECT:latest/g" "$DOCKER_DIR/$compose_file"
    portable_sed "s|DEFAULT_VOLUME_LOCATION|$DEFAULT_VOLUME_LOCATION|g" "$DOCKER_DIR/$compose_file"
    portable_sed "s|DEFAULT_STATIC_VOLUME|$DEFAULT_STATIC_VOLUME|g" "$DOCKER_DIR/$compose_file"
    portable_sed "s|DEFAULT_MEDIA_VOLUME|$DEFAULT_MEDIA_VOLUME|g" "$DOCKER_DIR/$compose_file"
done

# 8a. If using named volumes, ensure volumes section is uncommented
if [ "$VOLUME_MODE" = "named" ]; then
    for compose_file in "wagtail-compose.yml" "wagtail-dev-compose.yml"; do
        if grep -q "^# volumes:" "$DOCKER_DIR/$compose_file"; then
            portable_sed "/^# volumes:/s/^# //" "$DOCKER_DIR/$compose_file"
            portable_sed "/^#   ${PROJECT}_app_data:/s/^#   /  /" "$DOCKER_DIR/$compose_file"
            portable_sed "/^#   ${PROJECT}_static_data:/s/^#   /  /" "$DOCKER_DIR/$compose_file"
            portable_sed "/^#   ${PROJECT}_media_data:/s/^#   /  /" "$DOCKER_DIR/$compose_file"
        elif ! grep -q "volumes:" "$DOCKER_DIR/$compose_file"; then
            echo -e "\nvolumes:\n  ${PROJECT}_app_data:\n  ${PROJECT}_static_data:\n  ${PROJECT}_media_data:" >> "$DOCKER_DIR/$compose_file"
        fi
    done
fi

# 8c. Replace placeholders in .env file
portable_sed "s/PROJECT_NAME/$PROJECT/g" "$DOCKER_DIR/.env"
portable_sed "s/WEBSITE_DOMAIN/$DOMAIN/g" "$DOCKER_DIR/.env"
portable_sed "s|ALLOWED_HOSTS=your.domain.com,localhost|ALLOWED_HOSTS=$DOMAIN,localhost|g" "$DOCKER_DIR/.env"
portable_sed "s|SECRET_KEY=your-very-secret-key|SECRET_KEY=$SECRET_KEY|g" "$DOCKER_DIR/.env"

# 8d. Set default DJANGO_SETTINGS_MODULE to dev for easier development
portable_sed "s|DJANGO_SETTINGS_MODULE=PROJECT_NAME.settings.production|DJANGO_SETTINGS_MODULE=$PROJECT.settings.dev|g" "$DOCKER_DIR/.env"

echo "Wagtail app setup complete!"
echo "App directory: $APP_DIR"
echo "Docker config: $DOCKER_DIR"
echo "requirements.txt generated in $APP_DIR"
echo "Settings are split into: base.py, dev.py, and production.py"
echo "Remember to update your .env with real secrets and DB info."
echo ""
echo "Docker Compose files created:"
echo "- wagtail-compose.yml (production)"
echo "- wagtail-dev-compose.yml (development with auto-restart)"
echo "- wagtail-frontend-compose.yml (frontend development)"
echo ""
echo "Next steps:"
echo "1. Edit $DOCKER_DIR/.env with your database credentials and secrets"
echo "2. For production, change DJANGO_SETTINGS_MODULE to $PROJECT.settings.production"
echo "3. Run migrations: python manage.py migrate"
echo "4. Create a superuser: python manage.py createsuperuser"
echo "5. Use the application manager to start your Wagtail application:"
echo "   cd $APPLICATIONS_DIR && ./app_manage.sh"
deactivate
