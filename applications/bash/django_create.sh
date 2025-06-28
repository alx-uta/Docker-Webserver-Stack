#!/bin/bash
set -e

# Bash script to scaffold a new Django app with Docker support in /websites

# Get the script directory and ensure we're in the right place
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLICATIONS_DIR="$(dirname "$SCRIPT_DIR")"
BASE_DIR="$APPLICATIONS_DIR"

# 1. Ask for domain and Django project name
read -p "Enter the domain name (e.g., site1_com): " DOMAIN
read -p "Enter the Django project name (e.g., myproject): " PROJECT

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
APP_DIR="$SITE_DIR/app"
DOCKER_DIR="$SITE_DIR/docker"

# 3. Create directories
mkdir -p "$APP_DIR/static" "$APP_DIR/media"
mkdir -p "$DOCKER_DIR"

# 4. Create and activate venv, install Django
cd "$SITE_DIR"
python3 -m venv venv
source venv/bin/activate
cd "$APP_DIR"
pip install --upgrade pip
pip install django celery uvicorn redis python-dotenv watchdog flake8 isort black

# Generate requirements.txt
pip freeze > requirements.txt

# 5. Start the new Django project
django-admin startproject $PROJECT .

# 5b. Add celery.py and update __init__.py for Celery integration
cat > "$APP_DIR/$PROJECT/celery.py" <<EOF
import os
from celery import Celery

os.environ.setdefault('DJANGO_SETTINGS_MODULE', '$PROJECT.settings')

app = Celery('$PROJECT')
app.config_from_object('django.conf:settings', namespace='CELERY')
app.autodiscover_tasks()
EOF

echo -e "\nfrom .celery import app as celery_app\n\n__all__ = ('celery_app',)" >> "$APP_DIR/$PROJECT/__init__.py"


# 6. Check if template files exist
if [ ! -f "$BASE_DIR/django_app/Dockerfile" ]; then
    echo "Error: Django template files not found in $BASE_DIR/django_app/"
    echo "Please ensure the django_app directory exists with the required template files."
    exit 1
fi

# 7. Copy Dockerfile, .env.example, django-compose.yml files, and .gitignore into /docker and /app
cp "$BASE_DIR/django_app/Dockerfile" "$DOCKER_DIR/"
cp "$BASE_DIR/django_app/.env.example" "$DOCKER_DIR/.env"
cp "$BASE_DIR/django_app/django-compose.yml" "$DOCKER_DIR/django-compose.yml"
cp "$BASE_DIR/django_app/django-dev-compose.yml" "$DOCKER_DIR/django-dev-compose.yml"
cp "$BASE_DIR/django_app/django-frontend-compose.yml" "$DOCKER_DIR/django-frontend-compose.yml"
cp "$BASE_DIR/django_app/.gitignore" "$SITE_DIR/.gitignore"

# Copy VSCode configuration to app/.vscode
if [ -d "$BASE_DIR/django_app/vscode.example" ]; then
    cp -r "$BASE_DIR/django_app/vscode.example" "$APP_DIR/.vscode"
    echo "VSCode configuration copied to $APP_DIR/.vscode"
fi

# 8. Replace placeholders in all copied compose files
for compose_file in "django-compose.yml" "django-dev-compose.yml" "django-frontend-compose.yml"; do
    sed -i "s/PROJECT_NAME/$PROJECT/g" "$DOCKER_DIR/$compose_file"
    sed -i "s/WEBSITE_DOMAIN/$DOMAIN/g" "$DOCKER_DIR/$compose_file"
    # Replace image name with project-specific image
    sed -i "s/django-PROJECT_NAME:latest/django-$PROJECT:latest/g" "$DOCKER_DIR/$compose_file"
    # Update volume paths to match new structure
    sed -i "s|\.\/data\/django\/WEBSITE_DOMAIN\/app|..\/app|g" "$DOCKER_DIR/$compose_file"
    sed -i "s|\.\/data\/django\/WEBSITE_DOMAIN\/static|..\/app\/static|g" "$DOCKER_DIR/$compose_file"
    sed -i "s|\.\/data\/django\/WEBSITE_DOMAIN\/media|..\/app\/media|g" "$DOCKER_DIR/$compose_file"
done

# 8b. Replace placeholders in .env file
sed -i "s/PROJECT_NAME/$PROJECT/g" "$DOCKER_DIR/.env"
sed -i "s/WEBSITE_DOMAIN/$DOMAIN/g" "$DOCKER_DIR/.env"
sed -i "s|ALLOWED_HOSTS=your.domain.com,localhost|ALLOWED_HOSTS=$DOMAIN|g" "$DOCKER_DIR/.env"

SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(100))")
sed -i "s|SECRET_KEY=your-very-secret-key|SECRET_KEY=$SECRET_KEY|g" "$DOCKER_DIR/.env"

echo "Django app setup complete!"
echo "App directory: $APP_DIR"
echo "Docker config: $DOCKER_DIR"
echo "requirements.txt generated in $APP_DIR"
echo "Remember to update your .env with real secrets and DB info."
echo ""
echo "Docker Compose files created:"
echo "- django-compose.yml (production)"
echo "- django-dev-compose.yml (development with auto-restart)"
echo "- django-frontend-compose.yml (frontend development)"
echo ""
echo "Next steps:"
echo "1. Edit $DOCKER_DIR/.env with your database credentials and secrets"
echo "2. Use the application manager to start your Django application:"
echo "   cd $APPLICATIONS_DIR && ./app_manage.sh"
deactivate
