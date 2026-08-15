FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Install Git
RUN apt-get update && \
    apt-get install -y git

# Copy SSH keys and config for local development
# COPY ssh/id_rsa /root/.ssh/id_rsa
# COPY ssh/id_rsa.pub /root/.ssh/id_rsa.pub

# RUN chmod 600 /root/.ssh/id_rsa && \
#     chmod 644 /root/.ssh/id_rsa.pub

COPY . .
