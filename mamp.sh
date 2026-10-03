#!/bin/bash

# ==========================================
# MAMP-LITE (Persistent & Docker-like Logs)
# ==========================================

if [[ $(uname -m) == 'arm64' ]]; then
    BREW_PREFIX="/opt/homebrew"
else
    BREW_PREFIX="/usr/local"
fi

NGINX_CONF="$BREW_PREFIX/etc/nginx/nginx.conf"
VHOST_DIR="$BREW_PREFIX/etc/nginx/vhosts"
SITES_DIR="$HOME/Sites"

# Persistent Config Directories
MAMP_DIR="$HOME/.mamp-lite"
PROJECTS_DIR="$MAMP_DIR/projects"
PIDS_DIR="$MAMP_DIR/pids"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

show_help() {
    echo -e "${YELLOW}Usage:${NC} mamp {command}"
    echo ""
    echo "Global Commands:"
    echo "  setup          - Install dependencies, configure, and add 'mamp' alias"
    echo "  start          - Enable Nginx, MySQL, PHP"
    echo "  stop           - Disable Nginx, MySQL, PHP"
    echo "  restart        - Restart global services"
    echo "  status         - Check global service status"
    echo "  add [name]     - Create vhost & save project config (Interactive)"
    echo "  remove [name]  - Remove vhost, config, and stop services"
    echo ""
    echo "Project Commands (Run inside project dir or pass hostname):"
    echo "  project:start  - Start global services + persisted project services (Streams logs)"
    echo "  project:stop   - Stop persisted project services"
}

setup_env() {
    echo -e "${GREEN}[1/6] Checking Homebrew...${NC}"
    if ! command -v brew &> /dev/null; then echo -e "${RED}Homebrew not found.${NC}"; exit 1; fi

    echo -e "${GREEN}[2/6] Installing Nginx, MySQL, PHP, and Node.js...${NC}"
    brew install nginx mysql php node

    echo -e "${GREEN}[3/6] Creating Directories...${NC}"
    mkdir -p "$SITES_DIR" "$VHOST_DIR" "$PROJECTS_DIR" "$PIDS_DIR"
    echo "<?php phpinfo(); ?>" > "$SITES_DIR/index.php"

    echo -e "${GREEN}[4/6] Configuring Main Nginx & PHP-FPM...${NC}"
    if [ -f "$NGINX_CONF" ]; then cp "$NGINX_CONF" "$NGINX_CONF.bak"; fi

    cat <<EOT > "$NGINX_CONF"
worker_processes  1;
events { worker_connections  1024; }
http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;
    include $VHOST_DIR/*.conf;

    server {
        listen       8080;
        server_name  localhost;
        root   "$SITES_DIR";
        index  index.php index.html index.htm;
        location / { try_files \$uri \$uri/ =404; }
        location ~ \.php$ {
            fastcgi_pass   127.0.0.1:9000;
            fastcgi_index  index.php;
            fastcgi_param  SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            include        fastcgi_params;
        }
    }
}
EOT

    PHP_FPM_CONF=$(find "$BREW_PREFIX/etc/php" -name "www.conf" | head -n 1)
    if [ -n "$PHP_FPM_CONF" ]; then sed -i '' 's/^listen = .*/listen = 127.0.0.1:9000/' "$PHP_FPM_CONF"; fi

    SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    SHELL_RC="$HOME/.zshrc"
    if [ -n "$BASH_VERSION" ]; then SHELL_RC="$HOME/.bash_profile"; fi
    
    if ! grep -q "alias mamp=" "$SHELL_RC"; then
        echo "alias mamp='$SCRIPT_PATH'" >> "$SHELL_RC"
        echo -e "${GREEN}[5/6] Added 'mamp' alias to $SHELL_RC${NC}"
    fi

    echo -e "${GREEN}[6/6] Setup Complete! Run 'source $SHELL_RC' to use the 'mamp' command.${NC}"
}

add_vhost() {
    local HOSTNAME=$1
    local DIR_NAME=$(basename "$PWD")
    if [ -z "$HOSTNAME" ]; then HOSTNAME="${DIR_NAME}.test"; fi
    
    local ROOT_DIR="$PWD"
    if [ -d "$PWD/public" ] && [ -f "$PWD/public/index.php" ]; then
        ROOT_DIR="$PWD/public"
        echo -e "${GREEN}Detected Framework. Pointing Nginx to /public${NC}"
    fi

    cat <<EOT > "$VHOST_DIR/$HOSTNAME.conf"
server {
    listen       8080;
    server_name  $HOSTNAME;
    root   "$ROOT_DIR";
    index  index.php index.html index.htm;
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location ~ \.php$ {
        fastcgi_pass   127.0.0.1:9000;
        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include        fastcgi_params;
    }
}
EOT

    if ! grep -q "$HOSTNAME" /etc/hosts; then
        echo "127.0.0.1 $HOSTNAME # mamp-lite" | sudo tee -a /etc/hosts > /dev/null
        sudo dscacheutil -flushcache > /dev/null && sudo killall -HUP mDNSResponder > /dev/null
    fi

    if brew services list | grep -q "nginx.*started"; then brew services restart nginx > /dev/null; fi
    echo -e "\n${GREEN}Success!${NC} Nginx configured for: ${YELLOW}http://$HOSTNAME:8080${NC}"

    # --- INTERACTIVE PERSISTENCE PROMPT ---
    if [ -f "$PWD/artisan" ]; then
        IS_LARAVEL="true"
        echo -e "\n${YELLOW}--- Laravel Project Detected ---${NC}"
        
        read -p "Enable Vite dev server? (y/n) [y]: " choice_vite
        choice_vite=${choice_vite:-y}
        [[ "$choice_vite" =~ ^[Yy]$ ]] && ENABLE_VITE="true" || ENABLE_VITE="false"
        
        read -p "Enable Laravel Scheduler? (y/n) [n]: " choice_sched
        [[ "$choice_sched" =~ ^[Yy]$ ]] && ENABLE_SCHEDULE="true" || ENABLE_SCHEDULE="false"
        
        read -p "Enable Laravel Queue Worker? (y/n) [n]: " choice_queue
        [[ "$choice_queue" =~ ^[Yy]$ ]] && ENABLE_QUEUE="true" || ENABLE_QUEUE="false"
    else
        IS_LARAVEL="false"
        ENABLE_VITE="false"
        ENABLE_SCHEDULE="false"
        ENABLE_QUEUE="false"
    fi
    
    # Save configuration persistently
    cat <<EOT > "$PROJECTS_DIR/$HOSTNAME.conf"
HOSTNAME="$HOSTNAME"
ROOT_DIR="$ROOT_DIR"
IS_LARAVEL="$IS_LARAVEL"
ENABLE_VITE="$ENABLE_VITE"
ENABLE_SCHEDULE="$ENABLE_SCHEDULE"
ENABLE_QUEUE="$ENABLE_QUEUE"
EOT
    echo -e "${GREEN}Project configuration saved persistently.${NC}"
}

kill_project_services() {
    local HOSTNAME=$1
    local PIDS_FILE="$PIDS_DIR/$HOSTNAME.pids"
    if [ -f "$PIDS_FILE" ]; then
        while IFS=: read -r name pid; do
            echo -e "${YELLOW}Stopping $name (PID: $pid)...${NC}"
            kill "$pid" 2>/dev/null
            pkill -P "$pid" 2>/dev/null # Kill child processes (like node)
        done < "$PIDS_FILE"
        rm -f "$PIDS_FILE"
        echo -e "${GREEN}Project services stopped.${NC}"
    else
        echo -e "${YELLOW}No running services found for $HOSTNAME.${NC}"
    fi
}

project_start() {
    local HOSTNAME=$1
    if [ -z "$HOSTNAME" ]; then HOSTNAME="$(basename "$PWD").test"; fi
    
    local CONF_FILE="$PROJECTS_DIR/$HOSTNAME.conf"
    if [ ! -f "$CONF_FILE" ]; then
        echo -e "${RED}Project $HOSTNAME not found. Did you run 'mamp add'?${NC}"
        return 1
    fi
    
    source "$CONF_FILE"
    start_services
    
    local PIDS_FILE="$PIDS_DIR/$HOSTNAME.pids"
    > "$PIDS_FILE" # Clear previous PIDs
    
    cd "$ROOT_DIR" || exit 1
    
    if [ "$ENABLE_VITE" = "true" ]; then
        echo -e "${GREEN}Starting Vite...${NC}"
        npm run dev > .mamp-vite.log 2>&1 &
        echo "VITE:$!" >> "$PIDS_FILE"
    fi
    
    if [ "$ENABLE_SCHEDULE" = "true" ]; then
        echo -e "${GREEN}Starting Scheduler...${NC}"
        php artisan schedule:work > .mamp-schedule.log 2>&1 &
        echo "SCHEDULE:$!" >> "$PIDS_FILE"
    fi
    
    if [ "$ENABLE_QUEUE" = "true" ]; then
        echo -e "${GREEN}Starting Queue...${NC}"
        php artisan queue:work > .mamp-queue.log 2>&1 &
        echo "QUEUE:$!" >> "$PIDS_FILE"
    fi
    
    echo -e "${GREEN}Services started. Streaming logs... (Press Ctrl+C to stop)${NC}"
    
    # Trap Ctrl+C to cleanly kill background processes
    trap "kill_project_services '$HOSTNAME'; trap - SIGINT SIGTERM; exit" SIGINT SIGTERM
    
    # Stream logs in the foreground
    local LOG_FILES=()
    [ "$ENABLE_VITE" = "true" ] && LOG_FILES+=(".mamp-vite.log")
    [ "$ENABLE_SCHEDULE" = "true" ] && LOG_FILES+=(".mamp-schedule.log")
    [ "$ENABLE_QUEUE" = "true" ] && LOG_FILES+=(".mamp-queue.log")
    
    if [ ${#LOG_FILES[@]} -gt 0 ]; then
        tail -f "${LOG_FILES[@]}"
    else
        wait # If no logs to tail, just wait for background processes
    fi
}

project_stop() {
    local HOSTNAME=$1
    if [ -z "$HOSTNAME" ]; then HOSTNAME="$(basename "$PWD").test"; fi
    kill_project_services "$HOSTNAME"
}

remove_vhost() {
    local HOSTNAME=$1
    if [ -z "$HOSTNAME" ]; then echo -e "${RED}Please provide a hostname.${NC}"; return 1; fi
    
    kill_project_services "$HOSTNAME" > /dev/null
    rm -f "$VHOST_DIR/$HOSTNAME.conf"
    rm -f "$PROJECTS_DIR/$HOSTNAME.conf"
    rm -f "$PIDS_DIR/$HOSTNAME.pids"
    
    if grep -q "$HOSTNAME" /etc/hosts; then
        sudo sed -i '' "/$HOSTNAME # mamp-lite/d" /etc/hosts
        sudo dscacheutil -flushcache > /dev/null && sudo killall -HUP mDNSResponder > /dev/null
    fi
    if brew services list | grep -q "nginx.*started"; then brew services restart nginx > /dev/null; fi
    echo -e "${GREEN}Hostname $HOSTNAME removed and project cleaned up.${NC}"
}

# --- Global Services ---
start_services() { brew services start nginx mysql php > /dev/null; echo -e "${GREEN}Global services LIVE!${NC}"; }
stop_services() { brew services stop nginx mysql php > /dev/null; echo -e "${GREEN}Global services disabled.${NC}"; }
restart_services() { stop_services; sleep 2; start_services; }
show_status() { brew services list | grep -E 'nginx|mysql|php'; }

# --- phpMyAdmin Setup ---
setup_pma() {
    echo -e "${GREEN}[1/2] Installing phpMyAdmin via Homebrew...${NC}"
    brew install phpmyadmin
    
    echo -e "${GREEN}[2/2] Linking phpMyAdmin to your web root...${NC}"
    # $(brew --prefix) automatically detects Intel (/usr/local) or Apple Silicon (/opt/homebrew)
    local PMA_PATH="$(brew --prefix)/share/phpmyadmin"
    
    # Create a symlink in your ~/Sites directory
    ln -sfn "$PMA_PATH" "$SITES_DIR/phpmyadmin"
    
    echo -e "\n${GREEN}Success! phpMyAdmin is ready.${NC}"
    echo -e "Visit: ${YELLOW}http://localhost:8080/phpmyadmin${NC}"
    echo -e "Username: ${YELLOW}root${NC} | Password: ${YELLOW}(leave blank)${NC}"
}

# Command Router
case "$1" in
    setup)          setup_env ;;
    start)          start_services ;;
    stop)           stop_services ;;
    restart)        restart_services ;;
    status)         show_status ;;
    add)            add_vhost "$2" ;;
    remove)         remove_vhost "$2" ;;
    pma)            setup_pma ;;  # <--- ADD THIS LINE
    project:start)  project_start "$2" ;;
    project:stop)   project_stop "$2" ;;
    *)              show_help ;;
esac
