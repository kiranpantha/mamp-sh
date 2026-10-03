# MAMP-LITE (Nginx Edition)

A lightweight, on-demand, CLI-driven local development environment for macOS. It replaces heavy GUI applications with a fast, terminal-native stack using Nginx, MySQL, PHP, and Node.js via Homebrew, optimized for Laravel and Symfony.

## Features
- **On-Demand Services**: Start/stop Nginx, MySQL, and PHP to save RAM/CPU.
- **CLI Virtual Hosts**: Create local domains (e.g., `myapp.test`) instantly.
- **Smart Detection**: Auto-detects Laravel/Symfony and points Nginx to `/public`.
- **Live Log Streaming**: `project:start` streams Vite, Queue, and Scheduler logs like Docker.
- **Persistent Config**: Remembers which services you enabled per project.
- **Zero Ghost Processes**: Closing the terminal or pressing Ctrl+C cleanly kills all background tasks.
- **Global Alias**: Adds the `mamp` command to your terminal.

## Prerequisites
- macOS (Intel or Apple Silicon)
- Homebrew (https://brew.sh)

## Installation
1. Create the script: `nano ~/mamp-lite.sh` (paste the code, save, and exit).
2. Make it executable: `chmod +x ~/mamp-lite.sh`
3. Run setup: `~/mamp-lite.sh setup`
4. sudo ln -s ~/mamp-lite.sh /usr/local/bin/mamp
5. Activate alias: `source ~/.zshrc`

## Command Reference

### Global Commands
| Command | Description |
| :--- | :--- |
| `mamp start` | Start Nginx, MySQL, and PHP. |
| `mamp stop` | Stop all global services. |
| `mamp restart` | Restart all global services. |
| `mamp status` | Check running global services. |

### Virtual Host Commands
| Command | Description |
| :--- | :--- |
| `mamp add` | Create vhost for current dir (prompts for Laravel services). |
| `mamp add name` | Create vhost with a specific hostname. |
| `mamp remove name` | Delete vhost, clean `/etc/hosts`, and stop project services. |

### Project Commands
| Command | Description |
| :--- | :--- |
| `mamp project:start` | Start global + persisted project services. Streams logs live. |
| `mamp project:stop` | Stop all running project services for the current directory. |

## Workflow Guide
1. **Setup Project**: `cd ~/Sites/my-app` then run `mamp add`. Follow the prompts to enable Vite, Queue, or Scheduler.
2. **Start Working**: Run `mamp project:start`. Your terminal will stream all logs.
3. **Stop Working**: Press `Ctrl+C` to gracefully stop everything, or run `mamp project:stop` in a new terminal tab.

## Technical Details
- **Single PHP-FPM**: One PHP-FPM instance on port 9000 handles all directories. Nginx passes the absolute file path via `SCRIPT_FILENAME`.
- **Port 8080**: Used to avoid `sudo` requirements for binding to port 80. Access via `http://myapp.test:8080`.
- **Process Management**: Background services are tied to your terminal session. Closing the window sends a kill signal, preventing memory leaks.
- **Storage**: Configs are saved in `~/.mamp-lite/projects/` and PIDs in `~/.mamp-lite/pids/`.

## Troubleshooting
- **502 Bad Gateway**: Run `mamp status`. If PHP is stopped, run `mamp start`.
- **Logs not showing**: Ensure `npm install` and `composer install` have been run in the project.
- **Port 9000 in use**: Run `lsof -i :9000` to find and kill the conflicting process.

## Uninstallation
1. `mamp stop`
2. `brew uninstall nginx mysql php node`
3. `rm -rf ~/.mamp-lite ~/mamp-lite.sh`
4. Remove `alias mamp=...` from `~/.zshrc` or `~/.bash_profile`.
5. Edit `/etc/hosts` and remove lines ending with `# mamp-lite`.
