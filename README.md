# Docker Webserver Stack

A modular, production-ready Docker setup for running Django, WordPress, and PHP applications with shared services, persistent data, and easy management.

---

## **Quick Start**

### 1. **Initialize Environment**
```bash
cd webserver
./manage.sh
# Select option 3: "Initialize Environment"
```
This will:
- Create the Docker network (`webserver-network`)
- Set up data directories
- Create `.env` from `.env.example`
- Prompt you to configure environment variables

### 2. **Start Services**
```bash
./manage.sh
# Select option 1 (Development) or 2 (Production)
# Choose services to start or select "a" for all
```

### 3. **Create Your First Application**
```bash
cd ../applications
./bash/django_create.sh    # For Django
./bash/wordpress_create.sh # For WordPress  
./bash/php_create.sh       # For PHP
```

### 4. **Manage Applications**
```bash
./app_manage.sh
# Select your application and start it
```

---

## **Available Services**

### **Database Services**
- **PostgreSQL** - Primary database with health checks
- **MySQL** - Alternative database option  
- **Redis** - Caching and message broker

### **Storage & File Management**
- **SeaweedFS** - Distributed file system
  - Master: `http://localhost:9333` | Volume: `http://localhost:8080` | Filer: `http://localhost:8888`

### **Web Services**
- **Nginx Proxy Manager** - Reverse proxy with SSL
  - Web UI: `http://localhost:81` | HTTP: Port 80 | HTTPS: Port 443

### **Development Tools**
- **phpMyAdmin** - MySQL management at `http://localhost:28888`
- **Flower** - Celery monitoring at `http://localhost:5555`

---

## **Management Tools**

### **Service Management (`webserver/manage.sh`)**
1. **Development Environment** - Named volumes, easy reset
2. **Production Environment** - Persistent data in `./data/`
3. **Initialize Environment** - First-time setup
4. **Validate Environment** - Check configuration
5. **Backup Data** - Automated backups
6. **System Status** - Overview of running services
7. **List Containers** - Detailed container info
8. **Memory Analysis** - Performance monitoring

### **Application Management (`applications/app_manage.sh`)**
- **Auto-discovery** of deployed applications
- **Type detection** (Django/WordPress/PHP)
- **Container lifecycle** (start/stop/restart/rebuild)
- **Log monitoring** and shell access
- **Framework-specific commands** (Django migrations, Composer, etc.)
- **Safe removal** with volume preservation options

---

## **Environment Setup**

Copy `webserver/.env.example` to `webserver/.env` and configure:

```bash
# Database Configuration
POSTGRES_DB=your_database
POSTGRES_USER=your_user  
POSTGRES_PASSWORD=secure_password

MYSQL_ROOT_PASSWORD=secure_root_password
MYSQL_DATABASE=your_database
MYSQL_USER=your_user
MYSQL_PASSWORD=secure_password

# Redis & Storage
REDIS_PASSWORD=secure_redis_password

# SeaweedFS (uses PostgreSQL for metadata)
SEAWEED_POSTGRES_HOST=postgres
SEAWEED_POSTGRES_PORT=5432
SEAWEED_POSTGRES_USER=postgres
SEAWEED_POSTGRES_PASSWORD=secure_password
SEAWEED_POSTGRES_DB=seaweedfs
```

---

## **Application Types**

### **Django Applications**
- Full Django project with Celery integration
- PostgreSQL/MySQL database support
- Virtual environment and requirements management
- Management commands via app manager

### **WordPress Applications**  
- Standard WordPress installation
- MySQL database integration
- File uploads and theme management
- Plugin-ready configuration

### **PHP Applications**
- Modern PHP 8.1+ with Apache
- Composer dependency management
- Pre-configured extensions (PDO, MySQL, GD, etc.)
- Security headers and database connectivity

---

## **Development vs Production**

| Feature | Development | Production |
|---------|-------------|------------|
| **Data Storage** | Named Docker volumes | Bind mounts to `./data/` |
| **Use Case** | Local development, testing | Live deployments |
| **Reset/Rebuild** | Easy, disposable | Persistent, backed up |
| **Performance** | Optimized for iteration | Optimized for stability |

---

## **Troubleshooting**

### **Quick Fixes**
```bash
# Create network if missing
docker network create webserver-network

# Check environment variables
cd webserver && ./manage.sh # Option 4

# Memory analysis  
cd webserver && ./manage.sh # Option 8

# View application logs
cd applications && ./app_manage.sh # Select app → View logs
```

### **Common Issues**
- **Network Error** → Run network creation command above
- **Container Conflicts** → Use app manager to properly remove applications
- **Permission Errors** → `sudo chown -R $USER:$USER webserver/data/` (Linux/WSL)
- **High Memory Usage** → Use memory analysis tool, consider PostgreSQL over MySQL
- **Service Won't Start** → Check logs via management scripts

---

## **Project Structure**

```
DockerWebserverStack/
├── webserver/                    # Infrastructure services
│   ├── manage.sh                 # Service management
│   ├── docker/dev/               # Development configs  
│   ├── docker/live/              # Production configs
│   ├── config/                   # Service configuration
│   ├── data/                     # Production data (bind mounts)
│   └── .env                      # Service configuration
│
├── applications/                 # App creation & management
│   ├── app_manage.sh             # Application management
│   ├── bash/                     # Creation scripts
│   ├── django_app/               # Django templates
│   ├── wordpress_app/            # WordPress templates  
│   └── php_app/                  # PHP templates
│
└── websites/                     # Deployed applications
    └── <domain>/
        ├── app/                  # Django code
        ├── html/                 # WordPress/PHP code
        └── docker/               # App Docker config
```

---

## **Advanced Features**

### **Memory Usage Analysis**
```bash
cd webserver && ./manage.sh # Option 8
```
- Container memory usage sorting
- Optimization recommendations  
- System resource monitoring
- Database efficiency comparison

### **SeaweedFS Distributed Storage**
- PostgreSQL metadata storage
- S3-compatible API
- High availability and replication
- Automatic table creation

### **Application Isolation**
- Docker Compose project naming
- Container label-based tracking
- Network isolation per application
- Volume management per project

---

## **Useful Commands**

```bash
# Service management
cd webserver && ./manage.sh

# Application management  
cd applications && ./app_manage.sh

# Direct Docker commands
docker ps                      # List containers
docker network ls              # List networks  
docker system prune            # Clean up resources
docker stats                   # Resource usage

# SeaweedFS status
curl http://localhost:9333/cluster/status

# Database access
docker exec -it postgres psql -U postgres
```

---
