#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBSITES_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")/websites"

# Function to get project name from first service in compose file
get_project_name() {
    local domain="$1"
    local app_docker_dir="$WEBSITES_DIR/$domain/docker"
    
    # Find the first compose file
    local compose_file=""
    for file in "$app_docker_dir"/*-compose.yml "$app_docker_dir"/docker-compose.yml; do
        if [ -f "$file" ]; then
            compose_file="$file"
            break
        fi
    done
    
    if [ -z "$compose_file" ]; then
        # Fallback to domain-based name if no compose file found
        echo "$domain" | sed 's/\./_/g' | sed 's/-/_/g' | tr '[:upper:]' '[:lower:]'
        return
    fi
    
    # Extract first service name from compose file
    local first_service=$(awk '/^services:/{flag=1; next} flag && /^[[:space:]]+[a-zA-Z0-9_-]+:/{gsub(/^[[:space:]]+|:.*$/, ""); print; exit}' "$compose_file")
    
    if [ -n "$first_service" ] && [ "$first_service" != "services" ]; then
        echo "$first_service"
    else
        # Fallback to domain-based name if parsing fails
        echo "$domain" | sed 's/\./_/g' | sed 's/-/_/g' | tr '[:upper:]' '[:lower:]'
    fi
}

# Function to scan for deployed applications
scan_applications() {
    local apps=()
    
    if [ ! -d "$WEBSITES_DIR" ]; then
        print_warning "Websites directory not found: $WEBSITES_DIR"
        return 1
    fi
    
    for app_dir in "$WEBSITES_DIR"/*; do
        if [ -d "$app_dir" ] && [ -d "$app_dir/docker" ]; then
            local domain=$(basename "$app_dir")
            
            # Check for compose files
            local compose_files=()
            for file in "$app_dir/docker"/*-compose.yml "$app_dir/docker"/docker-compose.yml; do
                if [ -f "$file" ]; then
                    compose_files+=($(basename "$file"))
                fi
            done
            
            if [ ${#compose_files[@]} -gt 0 ]; then
                apps+=("$domain")
            fi
        fi
    done
    
    printf '%s\n' "${apps[@]}"
}

get_compose_files() {
    local domain="$1"
    local app_docker_dir="$WEBSITES_DIR/$domain/docker"
    local files=()
    if [ -d "$app_docker_dir" ]; then
        while IFS= read -r -d '' file; do
            files+=("$(basename "$file")")
        done < <(find "$app_docker_dir" -maxdepth 1 -type f \( -name '*-compose.yml' -o -name 'docker-compose.yml' \) -print0 | sort -z)
    fi
    printf '%s\n' "${files[@]}"
}

# Function to get container names for project
get_running_containers() {
    local project_name="$1"
    docker ps --filter "label=com.docker.compose.project=$project_name" --format "{{.Names}}" 2>/dev/null || true
}

# Function to check if project has running containers
is_project_running() {
    local project_name="$1"
    local containers=$(get_running_containers "$project_name")
    [ -n "$containers" ]
}

# Function to execute docker-compose with proper project name
execute_compose_cmd() {
    local domain="$1"
    local compose_file="$2"
    local action="$3"
    local extra_args="$4"
    
    local project_name=$(get_project_name "$domain")
    local app_dir="$WEBSITES_DIR/$domain"
    
    cd "$app_dir/docker"
    
    local compose_cmd="docker-compose -p $project_name"
    
    # Add env file if it exists
    if [ -f ".env" ]; then
        compose_cmd="$compose_cmd --env-file .env"
    fi
    
    compose_cmd="$compose_cmd -f $compose_file"
    
    case $action in
        "up")
            print_info "Starting $domain (project: $project_name)..."
            $compose_cmd up -d $extra_args
            ;;
        "down")
            print_info "Stopping $domain (project: $project_name)..."
            $compose_cmd down $extra_args
            ;;
        "stop")
            print_info "Stopping $domain (project: $project_name)..."
            $compose_cmd stop
            ;;
        "restart")
            print_info "Restarting $domain (project: $project_name)..."
            $compose_cmd restart
            ;;
        "logs")
            print_info "Showing logs for $domain (project: $project_name)..."
            $compose_cmd logs -f --tail=50
            ;;
        "ps")
            $compose_cmd ps
            ;;
        "build")
            print_info "Building $domain (project: $project_name)..."
            $compose_cmd build $extra_args
            ;;
        "pull")
            print_info "Pulling images for $domain (project: $project_name)..."
            $compose_cmd pull
            ;;
    esac
}

# Function to display application menu
show_app_menu() {
    local apps=($(scan_applications))
    
    echo
    print_info "Application Management Tool"
    echo "============================"
    echo
    
    if [ ${#apps[@]} -eq 0 ]; then
        print_warning "No deployed applications found in $WEBSITES_DIR"
        echo
        echo "Available actions:"
        echo "1) Create new Django application"
        echo "2) Create new WordPress application"
        echo "3) Create new PHP application"
        echo "4) Refresh application list"
        echo "q) Quit"
        return 1
    fi
    
    echo "Deployed applications:"
    local i=1
    for app in "${apps[@]}"; do
        local app_type="Unknown"
        local project_name=$(get_project_name "$app")
        
        # Detect application type
        if [ -f "$WEBSITES_DIR/$app/app/manage.py" ]; then
            app_type="Django"
        elif [ -f "$WEBSITES_DIR/$app/docker/wordpress-compose.yml" ]; then
            app_type="WordPress"
        elif [ -f "$WEBSITES_DIR/$app/docker/php-compose.yml" ]; then
            app_type="PHP"
        elif [ -d "$WEBSITES_DIR/$app/html" ]; then
            # Generic HTML/PHP if html directory exists but no specific compose file
            if [ -f "$WEBSITES_DIR/$app/html/index.php" ] || [ -f "$WEBSITES_DIR/$app/html/index.html" ]; then
                app_type="PHP/HTML"
            else
                app_type="WordPress"
            fi
        fi
        
        # Check if project is running
        local status="Stopped"
        if is_project_running "$project_name"; then
            status="Running"
        fi
        
        printf "%d) %s (%s) - %s [project: %s]\n" "$i" "$app" "$app_type" "$status" "$project_name"
        ((i++))
    done
    
    echo
    echo "Other actions:"
    echo "c) Create new application"
    echo "r) Refresh list"
    echo "s) Show all Docker projects"
    echo "q) Quit"
    echo
}

# Function to show all Docker projects
show_docker_projects() {
    echo
    print_info "All Docker Compose Projects"
    echo "============================"
    echo
    
    # Get all Docker Compose projects
    local projects=$(docker ps --filter "label=com.docker.compose.project" --format "{{.Label \"com.docker.compose.project\"}}" | sort | uniq)
    
    if [ -z "$projects" ]; then
        print_warning "No Docker Compose projects running"
        return
    fi
    
    for project in $projects; do
        local containers=$(docker ps --filter "label=com.docker.compose.project=$project" --format "{{.Names}}" | wc -l)
        echo "• $project ($containers containers)"
        docker ps --filter "label=com.docker.compose.project=$project" --format "  - {{.Names}} ({{.Status}})"
    done
}

# Function to show application actions
show_app_actions() {
    local domain="$1"
    local app_dir="$WEBSITES_DIR/$domain"
    local project_name=$(get_project_name "$domain")
    
    echo
    print_info "Managing application: $domain"
    echo "==============================="
    echo "Project name: $project_name"
    echo
    
    # Show application info
    local app_type="Unknown"
    if [ -f "$app_dir/app/manage.py" ]; then
        app_type="Django"
    elif [ -f "$app_dir/docker/wordpress-compose.yml" ]; then
        app_type="WordPress"
    elif [ -f "$app_dir/docker/php-compose.yml" ]; then
        app_type="PHP"
    elif [ -d "$app_dir/html" ]; then
        # Generic HTML/PHP if html directory exists but no specific compose file
        if [ -f "$app_dir/html/index.php" ] || [ -f "$app_dir/html/index.html" ]; then
            app_type="PHP/HTML"
        else
            app_type="WordPress"
        fi
    fi
    
    echo "Type: $app_type"
    echo "Location: $app_dir"
    
    # Show compose files
    local compose_files=($(get_compose_files "$domain"))
    echo "Compose files: ${compose_files[@]}"
    
    # Show container status
    echo
    print_info "Container Status:"
    local running_containers=$(get_running_containers "$project_name")
    if [ -n "$running_containers" ]; then
        echo "$running_containers" | while read container; do
            local status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
            echo "✓ $container: $status"
        done
    else
        echo "✗ No containers running for this project"
    fi
    
    echo
    echo "Available actions:"
    echo "1) Start application"
    echo "2) Stop application"
    echo "3) Restart application"
    echo "4) Redeploy application (rebuild)"
    echo "5) Build images"
    echo "6) View logs"
    echo "7) View status"
    echo "8) Open shell in container"
    echo "9) Remove application (keeps volumes)"
    echo "10) Remove application (delete volumes)"
    if [ "$app_type" = "Django" ]; then
        echo "11) Django management commands"
    elif [ "$app_type" = "PHP" ] || [ "$app_type" = "PHP/HTML" ]; then
        echo "11) PHP management commands"
    fi
    echo "b) Back to application list"
    echo "q) Quit"
    echo
}

# Function to execute application action
execute_app_action() {
    local domain="$1"
    local action="$2"
    local app_dir="$WEBSITES_DIR/$domain"
    local compose_files=($(get_compose_files "$domain"))
    local project_name=$(get_project_name "$domain")

    # Prompt user to select compose file(s) if more than one and action is relevant
    local selected_files=()
    if [ ${#compose_files[@]} -gt 1 ] && [[ "$action" =~ ^(start|stop|restart|redeploy|build|logs)$ ]]; then
        echo "Multiple compose files found:"
        local i=1
        for file in "${compose_files[@]}"; do
            echo "$i) $file"
            ((i++))
        done
        read -p "Select compose file(s) (comma-separated, or 'a' for all, default: 1): " file_choice
        if [ "$file_choice" = "a" ] || [ "$file_choice" = "A" ]; then
            selected_files=("${compose_files[@]}")
        elif [ -z "$file_choice" ]; then
            selected_files=("${compose_files[0]}")
        else
            IFS=',' read -ra idxs <<< "$file_choice"
            for idx in "${idxs[@]}"; do
                idx=$((idx-1))
                if [ $idx -ge 0 ] && [ $idx -lt ${#compose_files[@]} ]; then
                    selected_files+=("${compose_files[$idx]}")
                fi
            done
        fi
    else
        selected_files=("${compose_files[@]}")
    fi

    case $action in
        "start")
            for compose_file in "${selected_files[@]}"; do
                execute_compose_cmd "$domain" "$compose_file" "up"
            done
            ;;
        "stop")
            for compose_file in "${selected_files[@]}"; do
                execute_compose_cmd "$domain" "$compose_file" "stop"
            done
            ;;
        "restart")
            for compose_file in "${selected_files[@]}"; do
                execute_compose_cmd "$domain" "$compose_file" "restart"
            done
            ;;
        "redeploy")
            print_warning "Redeploying $domain (this will rebuild and recreate containers)..."
            read -p "Are you sure? (y/N): " confirm
            if [[ $confirm =~ ^[Yy]$ ]]; then
                for compose_file in "${selected_files[@]}"; do
                    execute_compose_cmd "$domain" "$compose_file" "down"
                    execute_compose_cmd "$domain" "$compose_file" "build" "--no-cache"
                    execute_compose_cmd "$domain" "$compose_file" "up" "--build"
                done
            else
                print_info "Redeploy cancelled."
            fi
            ;;
        "build")
            for compose_file in "${selected_files[@]}"; do
                execute_compose_cmd "$domain" "$compose_file" "build"
            done
            ;;
        "logs")
            for compose_file in "${selected_files[@]}"; do
                execute_compose_cmd "$domain" "$compose_file" "logs"
            done
            ;;
        "status")
            print_info "Status for $domain (project: $project_name):"
            for compose_file in "${compose_files[@]}"; do
                echo "--- $compose_file ---"
                execute_compose_cmd "$domain" "$compose_file" "ps"
            done
            echo
            print_info "Resource usage:"
            local containers=$(get_running_containers "$project_name")
            if [ -n "$containers" ]; then
                docker stats --no-stream $containers 2>/dev/null || true
            else
                echo "No running containers"
            fi
            ;;
        "shell")
            # Get running containers and let user choose
            local containers=$(get_running_containers "$project_name")
            if [ -z "$containers" ]; then
                print_error "No running containers found for $domain"
                return 1
            fi

            local containers_array=($containers)
            if [ ${#containers_array[@]} -eq 1 ]; then
                local target_container="${containers_array[0]}"
            else
                echo "Multiple containers found:"
                local i=1
                for container in "${containers_array[@]}"; do
                    echo "$i) $container"
                    ((i++))
                done
                read -p "Select container: " container_choice
                if [[ "$container_choice" =~ ^[0-9]+$ ]] && [ "$container_choice" -ge 1 ] && [ "$container_choice" -le "${#containers_array[@]}" ]; then
                    local target_container="${containers_array[$((container_choice-1))]}"
                else
                    print_error "Invalid selection"
                    return 1
                fi
            fi

            print_info "Opening shell in $target_container..."
            docker exec -it "$target_container" /bin/bash || docker exec -it "$target_container" /bin/sh
            ;;
        "remove")
            print_warning "Removing $domain containers (volumes will be preserved)..."
            read -p "Are you sure? (y/N): " confirm
            if [[ $confirm =~ ^[Yy]$ ]]; then
                for compose_file in "${compose_files[@]}"; do
                    execute_compose_cmd "$domain" "$compose_file" "down"
                done
            else
                print_info "Remove cancelled."
            fi
            ;;
        "remove_volumes")
            print_error "WARNING: This will delete ALL data for $domain!"
            print_warning "This action cannot be undone!"
            read -p "Type '$domain' to confirm deletion: " confirm
            if [ "$confirm" = "$domain" ]; then
                for compose_file in "${compose_files[@]}"; do
                    execute_compose_cmd "$domain" "$compose_file" "down" "-v"
                done
                print_success "Application and volumes removed"
            else
                print_info "Remove cancelled."
            fi
            ;;
        "django")
            django_management "$domain"
            ;;
        "php")
            php_management "$domain"
            ;;
    esac
}

# Add this function for debugging (you can remove it later)
debug_project_names() {
    local apps=($(scan_applications))
    
    echo
    print_info "Debug: Project Name Extraction"
    echo "=============================="
    
    for app in "${apps[@]}"; do
        local project_name=$(get_project_name "$app")
        local compose_files=($(get_compose_files "$app"))
        
        echo
        echo "Domain: $app"
        echo "Compose files: ${compose_files[@]}"
        echo "Project name: $project_name"
        
        # Show first few lines of compose file for verification
        local first_compose="$WEBSITES_DIR/$app/docker/${compose_files[0]}"
        if [ -f "$first_compose" ]; then
            echo "First compose file content (services section):"
            grep -A 3 "^services:" "$first_compose" || echo "No services section found"
        fi
        echo "---"
    done
}

# Function for Django management commands
django_management() {
    local domain="$1"
    local project_name=$(get_project_name "$domain")
    
    # Find Django container
    local containers=$(get_running_containers "$project_name")
    local django_container=""
    
    for container in $containers; do
        if [[ "$container" =~ django|web|app ]] && ! [[ "$container" =~ celery ]]; then
            django_container="$container"
            break
        fi
    done
    
    if [ -z "$django_container" ]; then
        print_error "No running Django container found for $domain"
        print_info "Available containers: $containers"
        return 1
    fi
    
    echo
    print_info "Django Management for $domain"
    echo "Container: $django_container"
    echo "Project: $project_name"
    echo
    echo "Common commands:"
    echo "1) Run migrations (migrate)"
    echo "2) Create migrations (makemigrations)"
    echo "3) Create superuser"
    echo "4) Collect static files"
    echo "5) Django shell"
    echo "6) Show migrations status"
    echo "7) Custom command"
    echo "b) Back"
    echo
    
    read -p "Select option: " django_choice
    
    case $django_choice in
        1)
            docker exec -it "$django_container" python manage.py migrate
            ;;
        2)
            docker exec -it "$django_container" python manage.py makemigrations
            ;;
        3)
            docker exec -it "$django_container" python manage.py createsuperuser
            ;;
        4)
            docker exec -it "$django_container" python manage.py collectstatic --noinput
            ;;
        5)
            docker exec -it "$django_container" python manage.py shell
            ;;
        6)
            docker exec -it "$django_container" python manage.py showmigrations
            ;;
        7)
            read -p "Enter Django command (without 'python manage.py'): " custom_cmd
            docker exec -it "$django_container" python manage.py $custom_cmd
            ;;
        b|B)
            return
            ;;
        *)
            print_error "Invalid choice!"
            ;;
    esac
}

# Function for PHP management commands
php_management() {
    local domain="$1"
    local project_name=$(get_project_name "$domain")
    
    # Find PHP container
    local containers=$(get_running_containers "$project_name")
    local php_container=""
    
    for container in $containers; do
        if [[ "$container" =~ php|web|app ]] && ! [[ "$container" =~ mysql|redis|nginx ]]; then
            php_container="$container"
            break
        fi
    done
    
    if [ -z "$php_container" ]; then
        print_error "No running PHP container found for $domain"
        print_info "Available containers: $containers"
        return 1
    fi
    
    echo
    print_info "PHP Management for $domain"
    echo "Container: $php_container"
    echo "Project: $project_name"
    echo
    echo "Common commands:"
    echo "1) Composer install"
    echo "2) Composer update"
    echo "3) Composer require package"
    echo "4) Run PHP info"
    echo "5) Check PHP version"
    echo "6) View PHP error log"
    echo "7) Run custom PHP command"
    echo "8) Install PHP extension"
    echo "9) Restart Apache"
    echo "b) Back"
    echo
    
    read -p "Select option: " php_choice
    
    case $php_choice in
        1)
            docker exec -it "$php_container" composer install
            ;;
        2)
            docker exec -it "$php_container" composer update
            ;;
        3)
            read -p "Enter package name (e.g., vendor/package): " package_name
            docker exec -it "$php_container" composer require "$package_name"
            ;;
        4)
            docker exec -it "$php_container" php -r "phpinfo();" | head -20
            ;;
        5)
            docker exec -it "$php_container" php --version
            ;;
        6)
            docker exec -it "$php_container" tail -50 /var/log/apache2/error.log 2>/dev/null || \
            docker exec -it "$php_container" tail -50 /var/log/php_errors.log 2>/dev/null || \
            echo "Error log not found"
            ;;
        7)
            read -p "Enter PHP command: " php_cmd
            docker exec -it "$php_container" php -r "$php_cmd"
            ;;
        8)
            read -p "Enter PHP extension name: " ext_name
            docker exec -it "$php_container" apt-get update && docker exec -it "$php_container" docker-php-ext-install "$ext_name"
            ;;
        9)
            docker exec -it "$php_container" service apache2 restart
            ;;
        b|B)
            return
            ;;
        *)
            print_error "Invalid choice!"
            ;;
    esac
}

# Function to handle application creation
handle_creation() {
    echo
    print_info "Application Creation"
    echo "==================="
    echo
    echo "1) Create Django application"
    echo "2) Create WordPress application"
    echo "3) Create PHP application"
    echo "b) Back to main menu"
    echo
    
    read -p "Select option: " create_choice
    
    case $create_choice in
        1)
            print_info "Starting Django application creation..."
            ./bash/django_create.sh
            ;;
        2)
            print_info "Starting WordPress application creation..."
            ./bash/wordpress_create.sh
            ;;
        3)
            print_info "Starting PHP application creation..."
            ./bash/php_create.sh
            ;;
        b|B)
            return
            ;;
        *)
            print_error "Invalid choice!"
            ;;
    esac
}

# Function to detect and use appropriate compose command
get_compose_command() {
    if command -v docker &> /dev/null && docker compose version &> /dev/null 2>&1; then
        echo "docker compose"
    elif command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    else
        return 1
    fi
}

# Main script
main() {
    # Check if docker is available
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    # Detect compose command
    COMPOSE_CMD=$(get_compose_command)
    if [ $? -ne 0 ]; then
        print_error "Neither 'docker compose' nor 'docker-compose' is available"
        print_info "Please install Docker Compose plugin or standalone docker-compose"
        exit 1
    fi
    
    print_info "Using compose command: $COMPOSE_CMD"
    
    while true; do
        if ! show_app_menu; then
            # No apps found, show creation menu
            read -p "Select option: " choice
            case $choice in
                1)
                    ./bash/django_create.sh
                    ;;
                2)
                    ./bash/wordpress_create.sh
                    ;;
                3)
                    ./bash/php_create.sh
                    ;;
                4)
                    continue
                    ;;
                q|Q)
                    print_info "Goodbye!"
                    exit 0
                    ;;
                *)
                    print_error "Invalid choice!"
                    ;;
            esac
        else
            # Apps found, show full menu
            local apps=($(scan_applications))
            read -p "Select application (1-${#apps[@]}) or option: " choice
            
            case $choice in
                c|C)
                    handle_creation
                    ;;
                r|R)
                    continue
                    ;;
                s|S)
                    show_docker_projects
                    read -p "Press Enter to continue..."
                    ;;
                q|Q)
                    print_info "Goodbye!"
                    exit 0
                    ;;
                *)
                    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#apps[@]}" ]; then
                        local selected_app="${apps[$((choice-1))]}"
                        
                        while true; do
                            show_app_actions "$selected_app"
                            read -p "Select action: " action_choice
                            
                            case $action_choice in
                                1)
                                    execute_app_action "$selected_app" "start"
                                    ;;
                                2)
                                    execute_app_action "$selected_app" "stop"
                                    ;;
                                3)
                                    execute_app_action "$selected_app" "restart"
                                    ;;
                                4)
                                    execute_app_action "$selected_app" "redeploy"
                                    ;;
                                5)
                                    execute_app_action "$selected_app" "build"
                                    ;;
                                6)
                                    execute_app_action "$selected_app" "logs"
                                    ;;
                                7)
                                    execute_app_action "$selected_app" "status"
                                    ;;
                                8)
                                    execute_app_action "$selected_app" "shell"
                                    ;;
                                9)
                                    execute_app_action "$selected_app" "remove"
                                    ;;
                                10)
                                    execute_app_action "$selected_app" "remove_volumes"
                                    ;;
                                11)
                                    # Check app type for management commands
                                    if [ -f "$WEBSITES_DIR/$selected_app/app/manage.py" ]; then
                                        execute_app_action "$selected_app" "django"
                                    elif [ -f "$WEBSITES_DIR/$selected_app/docker/php-compose.yml" ] || [ -f "$WEBSITES_DIR/$selected_app/html/index.php" ]; then
                                        execute_app_action "$selected_app" "php"
                                    else
                                        print_error "Invalid choice!"
                                    fi
                                    ;;
                                b|B)
                                    break
                                    ;;
                                q|Q)
                                    exit 0
                                    ;;
                                *)
                                    print_error "Invalid choice!"
                                    ;;
                            esac
                            
                            echo
                            read -p "Press Enter to continue..."
                        done
                    else
                        print_error "Invalid selection!"
                    fi
                    ;;
            esac
        fi
        
        echo
        read -p "Press Enter to continue..."
    done
}

# Run main function
main "$@"