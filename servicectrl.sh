#!/bin/bash
: '=======================================================
Service Control

Starts, stops, or restarts the app service.
=========================================================='

PYPROJECT="pyproject.toml"
SERVICE_FILE=""

if [ "$(uname -s)" = "Darwin" ]; then
	echo "Error: servicectrl.sh is not supported on macOS because it requires systemd." >&2
	exit 1
fi

# Get the current version from pyproject.toml
if [ -f "$PYPROJECT" ]; then
    CURRENT_VERSION=$(grep -E '^version *= *"' "$PYPROJECT" | head -1 | sed -E 's/^version *= *"([^"]+)".*$/\1/')
    PROJECT_NAME=$(grep -E '^name *= *"' "$PYPROJECT" | head -1 | sed -E 's/^name *= *"([^"]+)".*$/\1/')
    SERVICE=$(grep -E '^service_name *= *"' "$PYPROJECT" | head -1 | sed -E 's/^service_name *= *"([^"]+)".*$/\1/')
else
    echo "Error: $PYPROJECT not found."
    exit 1
fi

if [ -z "$SERVICE" ]; then
	echo "Error: service_name not defined in $PYPROJECT."
	exit 1
fi

SERVICE_FILE="/etc/systemd/system/$SERVICE.service"
UserID=${SUDO_USER:-$USER}

usage() {
	echo "Usage: $0 {start|stop|restart|reload|disable|enable|status|logs|edit|help}"
	exit 1
}

confirm_create_service_file() {
	echo "Service file '$SERVICE_FILE' does not exist."
	echo "A new file will be created with boilerplate content."
	printf "Continue? [y/N]: "
	read -r reply
	case "$reply" in
		y|Y|yes|YES|Yes)
			return 0
			;;
		*)
			echo "Aborted."
			exit 1
			;;
	esac
}

create_service_file() {
	sudo tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=$PROJECT_NAME service
After=network.target

[Service]
Type=simple
ExecStart=$(pwd)/launch.sh
WorkingDirectory=$(pwd)
User=$UserID
Environment=PYTHONUNBUFFERED=1
Environment=PATH=/home/$UserID/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
StandardOutput=journal
StandardError=journal

# Logging and restart behavior
Restart=on-failure        # Only restart on non-zero exit code
RestartSec=10             # Wait 10 seconds before restarting

# Limit restart attempts (3 times in 60 seconds)
StartLimitIntervalSec=60
StartLimitBurst=3

[Install]
WantedBy=multi-user.target
EOF
}

edit_service_file() {
	if [ ! -f "$SERVICE_FILE" ]; then
		confirm_create_service_file
		create_service_file
	fi

	sudo nano "$SERVICE_FILE"
}

help() {
	echo "Service Control - manage the '$SERVICE' systemd service"
	echo ""
	echo "Usage: $0 <command>"
	echo ""
	echo "Commands:"
	echo "  start    Start the service"
	echo "  stop     Stop the service"
	echo "  restart  Stop then start the service"
	echo "  reload   Reload the systemd daemon configuration (daemon-reexec + daemon-reload)"
	echo "  disable  Disable the service from starting at boot"
	echo "  enable   Enable the service to start at boot"
	echo "  status   Show the current status of the service"
	echo "  logs     Tail the live service logs (journalctl -f)"
	echo "  edit     Edit the systemd service file"
	echo "  help     Show this help message"
	exit 0
}

if [ $# -ne 1 ]; then
	usage
fi

if [ "$1" = "help" ]; then
	help
fi

echo "Managing service '$SERVICE' for project '$PROJECT_NAME' (v$CURRENT_VERSION) - action: $1"
case "$1" in
	start)
		sudo systemctl start "$SERVICE"
		;;
	stop)
		sudo systemctl stop "$SERVICE"
		;;
	restart)
		sudo systemctl stop "$SERVICE"
		sudo systemctl start "$SERVICE"
		;;
	reload)
		sudo systemctl daemon-reexec
		sudo systemctl daemon-reload
		;;
	disable)
		sudo systemctl disable "$SERVICE"
		;;
	enable)
		sudo systemctl enable "$SERVICE"
		;;
	status)
		sudo systemctl status "$SERVICE.service"
		;;
	logs)
		sudo journalctl -u "$SERVICE" -f
		;;
	edit)
		edit_service_file
		;;
	*)
		usage
		;;
esac
