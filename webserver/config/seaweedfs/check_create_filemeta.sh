#!/bin/sh
set -e

echo "Configuring SeaweedFS with PostgreSQL..."

# Check that all required environment variables are set
if [ -z "$SEAWEED_POSTGRES_HOST" ] || [ -z "$SEAWEED_POSTGRES_PORT" ] || [ -z "$SEAWEED_POSTGRES_USER" ] || [ -z "$SEAWEED_POSTGRES_PASSWORD" ] || [ -z "$SEAWEED_POSTGRES_DB" ]; then
    echo "ERROR: Missing required PostgreSQL environment variables"
    echo "Required: SEAWEED_POSTGRES_HOST, SEAWEED_POSTGRES_PORT, SEAWEED_POSTGRES_USER, SEAWEED_POSTGRES_PASSWORD, SEAWEED_POSTGRES_DB"
    exit 1
fi

# Creating filer.toml with environment variables
echo "Creating filer.toml with PostgreSQL configuration..."
cat > /etc/seaweedfs/filer.toml << EOF
# SeaweedFS Filer Configuration for PostgreSQL Metadata Store

[leveldb2]
enabled = false

[postgres]
enabled = true
createTable = true
username = "$SEAWEED_POSTGRES_USER"
password = "$SEAWEED_POSTGRES_PASSWORD"
database = "$SEAWEED_POSTGRES_DB"
hostname = "$SEAWEED_POSTGRES_HOST"
port = $SEAWEED_POSTGRES_PORT
sslmode = "disable"
EOF

echo "Checking/Creating filemeta table in PostgreSQL..."

# Set PostgreSQL connection variables
export PGPASSWORD="$SEAWEED_POSTGRES_PASSWORD"

# Wait for PostgreSQL to be ready
until pg_isready -h "$SEAWEED_POSTGRES_HOST" -p "$SEAWEED_POSTGRES_PORT" -U "$SEAWEED_POSTGRES_USER"; do
  echo "Waiting for PostgreSQL to be ready..."
  sleep 2
done

# Create the filemeta table if it doesn't exist
psql -h "$SEAWEED_POSTGRES_HOST" -p "$SEAWEED_POSTGRES_PORT" -U "$SEAWEED_POSTGRES_USER" -d "$SEAWEED_POSTGRES_DB" -c "
    CREATE TABLE IF NOT EXISTS filemeta (
        dirhash     BIGINT,
        name        VARCHAR(65535),
        directory   VARCHAR(65535),
        meta        bytea,
        PRIMARY KEY (dirhash, name)
    );"

echo "Table 'filemeta' created or already exists."
echo "SeaweedFS PostgreSQL configuration complete."
