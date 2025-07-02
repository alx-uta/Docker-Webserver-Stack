#!/bin/bash

set -e

# Check Bash version and require 4.0+ for associative arrays
if [ "${BASH_VERSION%%.*}" -lt 4 ]; then
    echo "Error: This script requires Bash 4.0 or higher for associative array support."
    echo "Current version: $BASH_VERSION"
    echo ""
    echo "On macOS, install newer Bash with:"
    echo "  brew install bash"
    echo "Then run with: bash manage.sh"
    exit 1
fi

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
PROJECT_ROOT="$SCRIPT_DIR"  # Now the script is in the project root
DOCKER_DIR="$SCRIPT_DIR/docker"  # Docker files are in subdirectory

# Available services in each environment
declare -A DEV_SERVICES
declare -A LIVE_SERVICES

# Store custom project names
declare -A PROJECT_NAMES

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

# Scan for available services
if [ -d "$DOCKER_DIR/dev" ]; then
    for file in "$DOCKER_DIR/dev"/*-compose.yml; do
        if [ -f "$file" ]; then
            service=$(basename "$file" -compose.yml)
            DEV_SERVICES["$service"]="dev/$service-compose.yml"
        fi
    done
fi

if [ -d "$DOCKER_DIR/live" ]; then
    for file in "$DOCKER_DIR/live"/*-compose.yml; do
        if [ -f "$file" ]; then
            service=$(basename "$file" -compose.yml)
            LIVE_SERVICES["$service"]="live/$service-compose.yml"
        fi
    done
fi

# Function to validate environment file
validate_env() {
    local env_file="$PROJECT_ROOT/.env"
    local missing_vars=()
    
    # Required variables
    local required_vars=(
        "POSTGRES_DB" "POSTGRES_USER" "POSTGRES_PASSWORD"
        "MYSQL_ROOT_PASSWORD" "MYSQL_DATABASE" "MYSQL_USER" "MYSQL_PASSWORD"
        "REDIS_PASSWORD"
    )
    
    print_info "Validating environment variables..."
    
    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}=" "$env_file" 2>/dev/null || grep -q "^${var}=$" "$env_file" 2>/dev/null; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        print_warning "Missing or empty environment variables:"
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
        done
        read -p "Continue anyway? (y/N): " confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            return 1
        fi
    else
        print_success "All required environment variables are set"
    fi
}

# Function to initialize environment
init_environment() {
    print_info "Initializing Docker Webserver Stack..."
    
    # Create network if it doesn't exist
    if ! docker network ls | grep -q webserver-network; then
        print_info "Creating webserver-network..."
        docker network create webserver-network
        print_success "Network created successfully"
    else
        print_info "Network webserver-network already exists"
    fi
    
    # Create data directories
    print_info "Creating data directories..."
    mkdir -p "$PROJECT_ROOT/data/mysql"
    mkdir -p "$PROJECT_ROOT/data/postgres"
    mkdir -p "$PROJECT_ROOT/data/redis"
    mkdir -p "$PROJECT_ROOT/data/npm/data"
    mkdir -p "$PROJECT_ROOT/data/npm/letsencrypt"
    mkdir -p "$(dirname "$PROJECT_ROOT")/websites"
    print_success "Data directories created"
    
    # Check if .env exists
    if [ ! -f "$PROJECT_ROOT/.env" ]; then
        if [ -f "$PROJECT_ROOT/.env.example" ]; then
            print_info "Creating .env from example..."
            cp "$PROJECT_ROOT/.env.example" "$PROJECT_ROOT/.env"
            print_warning "Please edit .env with your actual credentials!"
            read -p "Open .env file for editing now? (y/N): " edit_env
            if [[ $edit_env =~ ^[Yy]$ ]]; then
                "${EDITOR:-nano}" "$PROJECT_ROOT/.env"
            fi
        else
            print_error ".env.example file not found. Please create .env manually."
            return 1
        fi
    else
        print_info ".env file already exists"
    fi
    
    print_success "Environment initialization complete!"
    print_info "You can now use this script to manage your services."
}

show_memory_usage() {
    echo
    print_info "Container Memory Usage Analysis"
    echo "==============================="
    echo
    
    # Check if any containers are running
    if [ "$(docker ps -q | wc -l)" -eq 0 ]; then
        print_warning "No containers currently running"
        return
    fi
    
    print_info "Memory Usage by Container (sorted by usage):"
    echo
    docker stats --no-stream --format "table {{.Container}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.CPUPerc}}" | \
    (read -r header; echo "$header"; tail -n +1 | sort -k3 -nr)
    
    echo
    print_info "Top 3 Memory Consumers:"
    docker stats --no-stream --format "{{.Container}}: {{.MemUsage}} ({{.MemPerc}})" | \
    sort -k2 -nr | head -3 | while read line; do
        echo "  $line"
    done
    
    echo
    print_info "Memory Recommendations:"
    
    # Check for high memory usage containers
    local high_memory_containers=$(docker stats --no-stream --format "{{.Container}} {{.MemPerc}}" | \
    awk '$2 > 10 {print $1}' | tr '\n' ' ')
    
    if [ -n "$high_memory_containers" ]; then
        print_warning "High memory usage detected in: $high_memory_containers"
        echo "Consider the following optimizations:"
        
        for container in $high_memory_containers; do
            case $container in
                *mysql*)
                    echo "  • MySQL ($container): Add memory limits to compose file or switch to PostgreSQL"
                    ;;
                *postgres*)
                    echo "  • PostgreSQL ($container): Generally efficient, check for memory leaks in queries"
                    ;;
                *redis*)
                    echo "  • Redis ($container): Check data size and consider memory limits"
                    ;;
                *django*|*wordpress*)
                    echo "  • Application ($container): Check for memory leaks and optimize code"
                    ;;
                *)
                    echo "  • $container: Monitor for memory leaks and consider resource limits"
                    ;;
            esac
        done
    else
        print_success "All containers are using reasonable amounts of memory (<10%)"
    fi
    
    echo
    print_info "System Memory Info:"
    if command -v free &> /dev/null; then
        free -h | grep -E "Mem:|Swap:"
    else
        echo "System memory info not available (free command not found)"
    fi
    
    echo
    print_info "Docker System Resource Usage:"
    if command -v docker &> /dev/null; then
        docker system df 2>/dev/null || echo "Docker system info not available"
    fi
    
    echo
    print_info "Memory Optimization Tips:"
    echo "• PostgreSQL typically uses 50-80% less memory than MySQL"
    echo "• Consider adding memory limits to compose files for production"
    echo "• Use 'docker system prune' regularly to clean up unused resources"
    echo "• Monitor application containers for memory leaks"
}

# Function to list current containers
list_containers() {
    echo
    print_info "Current Docker Containers"
    echo "========================="
    echo
    
    # Check if any containers are running
    local running_containers=$(docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null)
    
    if [ "$(docker ps -q | wc -l)" -eq 0 ]; then
        print_warning "No containers currently running"
    else
        print_info "Running Containers:"
        echo "$running_containers"
    fi
    
    echo
    local stopped_count=$(docker ps -a -f "status=exited" -q | wc -l)
    if [ "$stopped_count" -gt 0 ]; then
        print_info "Stopped Containers: ($stopped_count)"
        docker ps -a -f "status=exited" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null
        echo
    fi
    
    # Show Docker Compose projects
    local compose_projects=$(docker ps --filter "label=com.docker.compose.project" --format "{{.Label \"com.docker.compose.project\"}}" | sort | uniq)
    
    if [ -n "$compose_projects" ]; then
        echo
        print_info "Active Docker Compose Projects:"
        for project in $compose_projects; do
            local containers_count=$(docker ps --filter "label=com.docker.compose.project=$project" --format "{{.Names}}" | wc -l)
            echo "• $project ($containers_count containers)"
        done
    fi
    
    # Show resource usage summary
    if [ "$(docker ps -q | wc -l)" -gt 0 ]; then
        echo
        print_info "Quick Resource Summary:"
        local total_cpu=$(docker stats --no-stream --format "{{.CPUPerc}}" | sed 's/%//' | awk '{sum += $1} END {printf "%.1f%%", sum}')
        local highest_mem=$(docker stats --no-stream --format "{{.MemPerc}}" | sed 's/%//' | sort -nr | head -1)
        echo "Total CPU Usage: $total_cpu"
        echo "Highest Memory Usage: ${highest_mem}%"
        echo
        echo "Use option 8 for detailed memory analysis"
    fi
}

# Function to backup data
backup_data() {
    local backup_dir="$PROJECT_ROOT/backups/$(date +%Y%m%d_%H%M%S)"
    
    print_info "Creating backup in $backup_dir..."
    mkdir -p "$backup_dir"
    
    # Check if containers are running before backup
    local postgres_running=$(docker ps --format "{{.Names}}" | grep "^postgres$" || true)
    local mysql_running=$(docker ps --format "{{.Names}}" | grep "^mysql$" || true)
    
    # Backup databases if containers are running
    if [ -n "$postgres_running" ]; then
        print_info "Backing up PostgreSQL database..."
        if docker exec postgres pg_dumpall -U "${POSTGRES_USER:-postgres}" > "$backup_dir/postgres_backup.sql" 2>/dev/null; then
            print_success "PostgreSQL backup completed"
        else
            print_warning "PostgreSQL backup failed or container not accessible"
        fi
    else
        print_warning "PostgreSQL container not running, skipping database backup"
    fi
    
    if [ -n "$mysql_running" ]; then
        print_info "Backing up MySQL database..."
        if docker exec mysql mysqldump --all-databases -u root -p"${MYSQL_ROOT_PASSWORD}" > "$backup_dir/mysql_backup.sql" 2>/dev/null; then
            print_success "MySQL backup completed"
        else
            print_warning "MySQL backup failed or container not accessible"
        fi
    else
        print_warning "MySQL container not running, skipping database backup"
    fi
    
    # Backup data directories
    if [ -d "$PROJECT_ROOT/data" ]; then
        print_info "Backing up data directories..."
        cd "$PROJECT_ROOT"
        tar -czf "$backup_dir/data_backup.tar.gz" data/ 2>/dev/null || print_warning "Some data directories could not be backed up"
        print_success "Data directories backup completed"
    fi
    
    print_success "Backup completed: $backup_dir"
    
    # Show backup size
    if command -v du &> /dev/null; then
        local backup_size=$(du -sh "$backup_dir" | cut -f1)
        print_info "Backup size: $backup_size"
    fi
}

# Function to display main menu
show_main_menu() {
    echo
    print_info "Docker Stack Management Tool"
    echo "============================="
    echo
    echo "Available options:"
    echo "1) Manage Development Environment (${#DEV_SERVICES[@]} services)"
    echo "2) Manage Live/Production Environment (${#LIVE_SERVICES[@]} services)"
    echo "3) Initialize Environment (setup network, directories, .env)"
    echo "4) Validate Environment Variables"
    echo "5) Backup Data"
    echo "6) System Status"
    echo "7) List Current Containers"
    echo "8) Memory Usage Analysis"
    echo "q) Quit"
    echo
}

# Function to display environment menu
show_environment_menu() {
    local env="$1"
    echo
    print_info "Available services in $env environment:"
    local i=1
    
    if [ "$env" = "dev" ]; then
        for service in "${!DEV_SERVICES[@]}"; do
            echo "$i) $service"
            ((i++))
        done
    else
        for service in "${!LIVE_SERVICES[@]}"; do
            echo "$i) $service"
            ((i++))
        done
    fi
    
    echo "a) Deploy ALL services"
    echo "b) Back to main menu"
    echo "q) Quit"
    echo
}

# Function to show action menu
show_action_menu() {
    local service="$1"
    local env="$2"
    echo
    print_info "Choose an action for $service ($env):"
    echo "1) Start/Deploy service"
    echo "2) Stop service (keeps containers)"
    echo "3) Restart service"
    echo "4) Redeploy (recreate containers, preserve volumes)"
    echo "5) View logs"
    echo "6) View status"
    echo "7) Remove service (keeps volumes)"
    echo "b) Back to service selection"
    echo "q) Quit"
    echo
}

# Function to show system status
show_system_status() {
    echo
    print_info "System Status"
    echo "============="
    echo
    
    # Docker network status
    print_info "Docker Networks:"
    if docker network ls | grep -q webserver-network; then
        echo "✓ webserver-network: EXISTS"
    else
        echo "✗ webserver-network: MISSING"
    fi
    echo
    
    # Running containers
    print_info "Running Containers:"
    local running_containers=$(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(postgres|mysql|redis|nginx-proxy-manager)" || echo "No relevant containers running")
    echo "$running_containers"
    echo
    
    # Volume usage
    print_info "Volume Usage:"
    if command -v du &> /dev/null && [ -d "$PROJECT_ROOT/data" ]; then
        du -sh "$PROJECT_ROOT/data"/* 2>/dev/null || echo "No data directories found"
    else
        echo "Cannot calculate volume usage"
    fi
    echo
    
    # Environment file status
    print_info "Environment Configuration:"
    if [ -f "$PROJECT_ROOT/.env" ]; then
        echo "✓ .env file: EXISTS"
        validate_env && echo "✓ Environment variables: VALID" || echo "✗ Environment variables: ISSUES FOUND"
    else
        echo "✗ .env file: MISSING"
    fi
    
    echo
    print_info "Quick Memory Check:"
    if [ "$(docker ps -q | wc -l)" -gt 0 ]; then
        local highest_mem_container=$(docker stats --no-stream --format "{{.Container}} {{.MemPerc}}" | sort -k2 -nr | head -1)
        echo "Highest memory usage: $highest_mem_container"
        echo "(Use option 8 for detailed memory analysis)"
    else
        echo "No containers running"
    fi
}

# Function to execute docker compose commands
execute_compose() {
    local compose_file="$1"
    local action="$2"
    local service_name="$3"
    local service_key="${service_name}_$(basename "$compose_file" .yml)"
    
    cd "$DOCKER_DIR"
    
    case $action in
        "start")
            print_info "Starting $service_name with $compose_file..."
            
            # Check if we have a saved project name for this service
            local saved_project_name="${PROJECT_NAMES[$service_key]}"
            
            echo
            print_info "Project Name Configuration:"
            echo "The project name is used with '$COMPOSE_CMD -p <project_name>' to isolate containers."
            echo "Default would be: $(basename "$(pwd)")"
            
            if [ -n "$saved_project_name" ]; then
                echo "Previously used: $saved_project_name"
                read -p "Enter project name (press Enter to use '$saved_project_name', or type new name): " custom_project_name
                if [ -z "$custom_project_name" ]; then
                    custom_project_name="$saved_project_name"
                fi
            else
                read -p "Enter custom project name (or press Enter for default): " custom_project_name
            fi
            
            if [ -n "$custom_project_name" ]; then
                # Validate project name
                if [[ ! "$custom_project_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                    print_error "Invalid project name! Use only letters, numbers, hyphens, and underscores."
                    return 1
                fi
                
                # Save the project name for future use
                PROJECT_NAMES[$service_key]="$custom_project_name"
                
                print_info "Using project name: $custom_project_name"
                $COMPOSE_CMD --env-file "$PROJECT_ROOT/.env" -p "$custom_project_name" -f "$compose_file" up -d
            else
                print_info "Using default project name"
                $COMPOSE_CMD --env-file "$PROJECT_ROOT/.env" -f "$compose_file" up -d
            fi
            ;;
        "stop"|"restart"|"redeploy"|"logs"|"status"|"remove")
            local saved_project_name="${PROJECT_NAMES[$service_key]}"
            local project_name=""
            
            if [ -n "$saved_project_name" ]; then
                print_info "Found saved project name: $saved_project_name"
                read -p "Use saved project name '$saved_project_name'? (Y/n): " use_saved
                if [[ ! $use_saved =~ ^[Nn]$ ]]; then
                    project_name="$saved_project_name"
                else
                    read -p "Enter project name (or press Enter for default): " project_name
                fi
            else
                echo
                print_info "If you used a custom project name, enter it now:"
                read -p "Enter project name (or press Enter for default): " project_name
            fi
            
            # Execute the appropriate action with or without project name
            case $action in
                "stop")
                    print_info "Stopping $service_name..."
                    if [ -n "$project_name" ]; then
                        $COMPOSE_CMD --env-file "$PROJECT_ROOT/.env" -p "$project_name" -f "$compose_file" stop
                    else
                        $COMPOSE_CMD --env-file "$PROJECT_ROOT/.env" -f "$compose_file" stop
                    fi
                    ;;
                "restart")
                    print_info "Restarting $service_name..."
                    if [ -n "$project_name" ]; then
                        $COMPOSE_CMD --env-file "$PROJECT_ROOT/.env" -p "$project_name" -f "$compose_file" restart
                    else
                        $COMPOSE_CMD --env-file "$PROJECT_ROOT/.env" -f "$compose_file" restart
                    fi
                    ;;
                "redeploy")
                    print_warning "Redeploying $service_name (this will recreate containers but preserve volumes)..."
                    read -p "Are you sure you want to redeploy? (y/N): " confirm
                    if [[ $confirm =~ ^[Yy]$ ]]; then
                        if [ -n "$project_name" ]; then
                            $COMPOSE_CMD --env-file "$PROJECT_ROOT/.env" -p "$project_name" -f "$compose_file" up -d --force-recreate
                        else
                            $COMPOSE_CMD --env-file "$PROJECT_ROOT/.env" -f "$compose_file" up -d --force-recreate
                        fi
                    else
                        print_info "Redeploy cancelled."
                        return
                    fi
                    ;;
                "logs")
                    print_info "Showing logs for $service_name..."
                    if [ -n "$project_name" ]; then
                        $COMPOSE_CMD --env-file "$PROJECT_ROOT/.env" -p "$project_name" -f "$compose_file" logs -f --tail=50
                    else
                        $COMPOSE_CMD --env-file "$PROJECT_ROOT/.env" -f "$compose_file" logs -f --tail=50
                    fi
                    ;;
                "status")
                    print_info "Service status for $service_name:"
                    if [ -n "$project_name" ]; then
                        $COMPOSE_CMD --env-file "$PROJECT_ROOT/.env" -p "$project_name" -f "$compose_file" ps
                        echo
                        print_info "Resource usage:"
                        local containers=$($COMPOSE_CMD --env-file "$PROJECT_ROOT/.env" -p "$project_name" -f "$compose_file" ps -q)
                    else
                        $COMPOSE_CMD --env-file "$PROJECT_ROOT/.env" -f "$compose_file" ps
                        echo
                        print_info "Resource usage:"
                        local containers=$($COMPOSE_CMD --env-file "$PROJECT_ROOT/.env" -f "$compose_file" ps -q)
                    fi
                    
                    if [ -n "$containers" ]; then
                        docker stats --no-stream $containers 2>/dev/null || true
                    fi
                    ;;
                "remove")
                    print_warning "Removing $service_name (volumes will be preserved)..."
                    read -p "Are you sure you want to remove? (y/N): " confirm
                    if [[ $confirm =~ ^[Yy]$ ]]; then
                        if [ -n "$project_name" ]; then
                            $COMPOSE_CMD --env-file "$PROJECT_ROOT/.env" -p "$project_name" -f "$compose_file" down
                        else
                            $COMPOSE_CMD --env-file "$PROJECT_ROOT/.env" -f "$compose_file" down
                        fi
                        # Clear the saved project name after removal
                        unset PROJECT_NAMES[$service_key]
                    else
                        print_info "Remove cancelled."
                        return
                    fi
                    ;;
            esac
            ;;
        "start_all")
            print_info "Starting all services in $service_name environment..."
            
            echo
            print_info "Project Name Configuration for ALL services:"
            echo "This will apply the same project name to all services in this environment."
            read -p "Enter custom project name for all services (or press Enter for default): " custom_project_name
            
            if [ -n "$custom_project_name" ]; then
                if [[ ! "$custom_project_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                    print_error "Invalid project name! Use only letters, numbers, hyphens, and underscores."
                    return 1
                fi
                print_info "Using custom project name '$custom_project_name' for all services"
            fi
            
            if [ "$service_name" = "dev" ]; then
                for service in "${!DEV_SERVICES[@]}"; do
                    local file="${DEV_SERVICES[$service]}"
                    print_info "Starting $service..."
                    if [ -n "$custom_project_name" ]; then
                        $COMPOSE_CMD --env-file "$PROJECT_ROOT/.env" -p "${custom_project_name}-${service}" -f "$file" up -d
                        # Save project name for individual service management
                        PROJECT_NAMES["${service}_$(basename "$file" .yml)"]="${custom_project_name}-${service}"
                    else
                        $COMPOSE_CMD --env-file "$PROJECT_ROOT/.env" -f "$file" up -d
                    fi
                done
            else
                for service in "${!LIVE_SERVICES[@]}"; do
                    local file="${LIVE_SERVICES[$service]}"
                    print_info "Starting $service..."
                    if [ -n "$custom_project_name" ]; then
                        $COMPOSE_CMD --env-file "$PROJECT_ROOT/.env" -p "${custom_project_name}-${service}" -f "$file" up -d
                        # Save project name for individual service management
                        PROJECT_NAMES["${service}_$(basename "$file" .yml)"]="${custom_project_name}-${service}"
                    else
                        $COMPOSE_CMD --env-file "$PROJECT_ROOT/.env" -f "$file" up -d
                    fi
                done
            fi
            ;;
    esac
}

# Function to handle service selection
handle_service_selection() {
    local env="$1"
    local selection="$2"
    
    # Convert associative array to indexed array for selection
    local services_array=()
    local files_array=()
    
    if [ "$env" = "dev" ]; then
        for service in "${!DEV_SERVICES[@]}"; do
            services_array+=("$service")
            files_array+=("${DEV_SERVICES[$service]}")
        done
    else
        for service in "${!LIVE_SERVICES[@]}"; do
            services_array+=("$service")
            files_array+=("${LIVE_SERVICES[$service]}")
        done
    fi
    
    if [ "$selection" = "a" ] || [ "$selection" = "A" ]; then
        execute_compose "" "start_all" "$env"
        return
    fi
    
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "${#services_array[@]}" ]; then
        print_error "Invalid selection!"
        return 1
    fi
    
    local service_name="${services_array[$((selection-1))]}"
    local compose_file="${files_array[$((selection-1))]}"
    
    print_success "Selected: $service_name ($env environment)"
    
    # Check if compose file exists
    if [ ! -f "$DOCKER_DIR/$compose_file" ]; then
        print_error "Compose file not found: $DOCKER_DIR/$compose_file"
        return 1
    fi
    
    while true; do
        show_action_menu "$service_name" "$env"
        read -p "Select action: " action_choice
        
        case $action_choice in
            1)
                execute_compose "$compose_file" "start" "$service_name"
                ;;
            2)
                execute_compose "$compose_file" "stop" "$service_name"
                ;;
            3)
                execute_compose "$compose_file" "restart" "$service_name"
                ;;
            4)
                execute_compose "$compose_file" "redeploy" "$service_name"
                ;;
            5)
                execute_compose "$compose_file" "logs" "$service_name"
                ;;
            6)
                execute_compose "$compose_file" "status" "$service_name"
                ;;
            7)
                execute_compose "$compose_file" "remove" "$service_name"
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
}

# Function to handle environment selection
handle_environment() {
    local selection="$1"
    
    case $selection in
        1)
            if [ ${#DEV_SERVICES[@]} -eq 0 ]; then
                print_error "No development services found!"
                return 1
            fi
            
            while true; do
                show_environment_menu "dev"
                read -p "Select service (1-${#DEV_SERVICES[@]}) or option: " service_choice
                
                case $service_choice in
                    b|B)
                        break
                        ;;
                    q|Q)
                        exit 0
                        ;;
                    a|A)
                        execute_compose "" "start_all" "dev"
                        read -p "Press Enter to continue..."
                        ;;
                    *)
                        handle_service_selection "dev" "$service_choice"
                        ;;
                esac
            done
            ;;
        2)
            if [ ${#LIVE_SERVICES[@]} -eq 0 ]; then
                print_error "No live/production services found!"
                return 1
            fi
            
            while true; do
                show_environment_menu "live"
                read -p "Select service (1-${#LIVE_SERVICES[@]}) or option: " service_choice
                
                case $service_choice in
                    b|B)
                        break
                        ;;
                    q|Q)
                        exit 0
                        ;;
                    a|A)
                        execute_compose "" "start_all" "live"
                        read -p "Press Enter to continue..."
                        ;;
                    *)
                        handle_service_selection "live" "$service_choice"
                        ;;
                esac
            done
            ;;
        3)
            init_environment
            read -p "Press Enter to continue..."
            ;;
        4)
            if [ -f "$PROJECT_ROOT/.env" ]; then
                validate_env
            else
                print_error ".env file not found. Run option 3 to initialize environment first."
            fi
            read -p "Press Enter to continue..."
            ;;
        5)
            backup_data
            read -p "Press Enter to continue..."
            ;;
        6)
            show_system_status
            read -p "Press Enter to continue..."
            ;;
        7)
            list_containers
            read -p "Press Enter to continue..."
            ;;
        8)
            show_memory_usage
            read -p "Press Enter to continue..."
            ;;
        *)
            print_error "Invalid selection!"
            return 1
            ;;
    esac
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
    print_info "Found ${#DEV_SERVICES[@]} dev services and ${#LIVE_SERVICES[@]} live services"
    
    while true; do
        show_main_menu
        read -p "Select option (1-8) or 'q' to quit: " choice
        
        case $choice in
            q|Q)
                print_info "Goodbye!"
                exit 0
                ;;
            1|2|3|4|5|6|7|8)
                handle_environment "$choice"
                ;;
            *)
                print_error "Invalid choice!"
                ;;
        esac
    done
}

# Run main function
main "$@"