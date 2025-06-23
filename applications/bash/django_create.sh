#!/bin/bash
set -e

# Bash script to scaffold a new Django app with Docker support in /websites

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
BASE_DIR="$(pwd)"
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
pip install django celery uvicorn redis python-dotenv

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


# 6. Copy Dockerfile, .env.example, django-compose.yml, and .gitignore into /docker and /app
cp "$BASE_DIR/django_app/Dockerfile" "$DOCKER_DIR/"
cp "$BASE_DIR/django_app/.env.example" "$DOCKER_DIR/.env"
cp "$BASE_DIR/django_app/django-compose.yml" "$DOCKER_DIR/django-compose.yml"
cp "$BASE_DIR/django_app/.gitignore" "$SITE_DIR/.gitignore"

# 7. Replace placeholders in copied files
sed -i "s/PROJECT_NAME/$PROJECT/g" "$DOCKER_DIR/django-compose.yml"
sed -i "s/WEBSITE_DOMAIN/$DOMAIN/g" "$DOCKER_DIR/django-compose.yml"
sed -i "s/PROJECT_NAME/$PROJECT/g" "$DOCKER_DIR/.env"
sed -i "s/WEBSITE_DOMAIN/$DOMAIN/g" "$DOCKER_DIR/.env"
sed -i "s|ALLOWED_HOSTS=your.domain.com,localhost|ALLOWED_HOSTS=$DOMAIN|g" "$DOCKER_DIR/.env"

SECRET_KEY=$(python3 -c "import secrets; print(''.join(secrets.choice('abcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*(-_=+)') for i in range(50)))")
sed -i "s|SECRET_KEY=your-very-secret-key|SECRET_KEY=$SECRET_KEY|g" "$DOCKER_DIR/.env"

# 8. Replace image name with project-specific image in django-compose.yml
sed -i "s/django-latest-image:latest/django-$PROJECT:latest/g" "$DOCKER_DIR/django-compose.yml"
sed -i "s|ALLOWED_HOSTS=your.domain.com,localhost|ALLOWED_HOSTS=$DOMAIN|g" "$DOCKER_DIR/.env"

# 9. Update volume paths in django-compose.yml to match new structure
sed -i "s|\.\/data\/django\/WEBSITE_DOMAIN\/app|..\/app|g" "$DOCKER_DIR/django-compose.yml"
sed -i "s|\.\/data\/django\/WEBSITE_DOMAIN\/static|..\/app\/static|g" "$DOCKER_DIR/django-compose.yml"
sed -i "s|\.\/data\/django\/WEBSITE_DOMAIN\/media|..\/app\/media|g" "$DOCKER_DIR/django-compose.yml"
sed -i "s/container_name: django_app/container_name: $PROJECT/g" "$DOCKER_DIR/django-compose.yml"

echo "Django app setup complete!"
echo "App directory: $APP_DIR"
echo "Docker config: $DOCKER_DIR"
echo "requirements.txt generated in $APP_DIR"
echo "Remember to update your .env with real secrets and DB info."
deactivate
