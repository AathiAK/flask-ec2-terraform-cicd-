#!/bin/bash
set -e

# Configuration
APP_DIR="/opt/flask-app"
APP_USER="ubuntu"
VENV_DIR="$APP_DIR/venv"
LOG_DIR="/var/log/flask-app"

echo "Starting deployment..."

# Create necessary directories
sudo mkdir -p $APP_DIR
sudo mkdir -p $LOG_DIR
sudo chown -R $APP_USER:$APP_USER $APP_DIR
sudo chown -R $APP_USER:$APP_USER $LOG_DIR

# Copy application files
echo "Copying application files..."
sudo cp -r /tmp/app/* $APP_DIR/
sudo chown -R $APP_USER:$APP_USER $APP_DIR

# Set up Python virtual environment
echo "Setting up Python virtual environment..."
cd $APP_DIR
python3 -m venv $VENV_DIR
source $VENV_DIR/bin/activate

# Install dependencies
echo "Installing Python dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

# Create systemd service file
echo "Creating systemd service..."
sudo tee /etc/systemd/system/flask-app.service > /dev/null <<EOF
[Unit]
Description=Flask Application
After=network.target

[Service]
Type=notify
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$APP_DIR
Environment="PATH=$VENV_DIR/bin"
Environment="S3_BUCKET_NAME=${S3_BUCKET_NAME}"
Environment="ENVIRONMENT=${ENVIRONMENT:-production}"
ExecStart=$VENV_DIR/bin/gunicorn --workers 3 --bind 127.0.0.1:5000 --timeout 60 --access-logfile $LOG_DIR/access.log --error-logfile $LOG_DIR/error.log app:app
ExecReload=/bin/kill -s HUP \$MAINPID
KillMode=mixed
TimeoutStopSec=5
PrivateTmp=true
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Configure Nginx
echo "Configuring Nginx..."
sudo tee /etc/nginx/sites-available/flask-app > /dev/null <<'EOF'
server {
    listen 80;
    server_name _;

    client_max_body_size 100M;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location /health {
        proxy_pass http://127.0.0.1:5000/health;
        access_log off;
    }
}
EOF

# Enable Nginx site
sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -sf /etc/nginx/sites-available/flask-app /etc/nginx/sites-enabled/

# Test Nginx configuration
echo "Testing Nginx configuration..."
sudo nginx -t

# Reload systemd and start services
echo "Starting services..."
sudo systemctl daemon-reload
sudo systemctl enable flask-app
sudo systemctl restart flask-app
sudo systemctl restart nginx

# Wait for application to start
echo "Waiting for application to start..."
sleep 5

# Check service status
echo "Checking service status..."
sudo systemctl status flask-app --no-pager || true

# Test application
echo "Testing application..."
curl -f http://localhost/health || {
    echo "Application health check failed!"
    echo "Flask app logs:"
    sudo journalctl -u flask-app -n 50 --no-pager
    exit 1
}

echo "Deployment completed successfully!"
