#!/bin/bash
: '=======================================================
Service Control

Starts, stops, or restarts the app service.
=========================================================='

PYPROJECT="pyproject.toml"
SERVICE_FILE=""

# Basic sanity checks 
if [ "$(uname -s)" = "Darwin" ]; then
	echo "Error: servicectrl.sh is not supported on macOS because it requires systemd." >&2
	exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
	echo "Error: this script requires root privileges. Please run with sudo." >&2
	exit 1
fi

# Get the current working directory
CURRENT_DIR=$(pwd)

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
	echo "Usage: $0 {start|stop|restart|reload|disable|enable|status|is-active|logs|edit|help}"
	echo "       $0 deploy <environment>"
	exit 1
}

edit_service_file() {
	if [ ! -f "$SERVICE_FILE" ]; then
		echo "Service file '$SERVICE_FILE' does not exist."
		echo "Use the deploy command to create it, or edit it manually."
	fi

	nano "$SERVICE_FILE"
}

deploy_service() {
	environment="$1"
	template="$CURRENT_DIR/deploy/$environment/$PROJECT_NAME.service"

	if [ ! -f "$template" ]; then
		echo "Error: service template '$template' not found." >&2
		exit 1
	fi

	echo "Deploying service '$SERVICE' from '$template' to '$SERVICE_FILE', then reloading, enabling, and starting it."
	cp "$template" "$SERVICE_FILE"
	systemctl daemon-reexec
	systemctl daemon-reload
	systemctl enable "$SERVICE"
	systemctl restart "$SERVICE"
}

help() {
	echo "Service Control - manage the '$SERVICE' systemd service"
	echo ""
	echo "Usage: $0 <command>"
	echo ""
	echo "Commands:"
	echo "  edit     			  Create or edit the systemd service file"
	echo "  deploy <environment>  Deploy the service (create service file, enable, and start) using the specified environment template (e.g., sydneyapp)"
	echo "  start    			  Start the service"
	echo "  stop    			  Stop the service"
	echo "  restart 			  Stop then start the service"
	echo "  reload  			  Reload the systemd daemon configuration (daemon-reexec + daemon-reload)"
	echo "  disable 			  Disable the service from starting at boot"
	echo "  enable  			  Enable the service to start at boot"
	echo "  status  			  Show the current status of the service"
	echo "  is-active			  Show whether the service is active (running)"
	echo "  logs    			  Tail the live service logs (journalctl -f)"
	echo "  help     			  Show this help message"
	exit 0
}

if [ "$1" = "deploy" ]; then
	if [ $# -ne 2 ]; then
		usage
	fi
elif [ $# -ne 1 ]; then
	usage
fi

if [ "$1" = "help" ]; then
	help
fi

echo "Managing service '$SERVICE' for project '$PROJECT_NAME' (v$CURRENT_VERSION) - action: $1"
case "$1" in
	start)
		systemctl start "$SERVICE"
		;;
	stop)
		systemctl stop "$SERVICE"
		;;
	restart)
		systemctl stop "$SERVICE"
		systemctl start "$SERVICE"
		;;
	reload)
		systemctl daemon-reexec
		systemctl daemon-reload
		;;
	disable)
		systemctl disable "$SERVICE"
		;;
	enable)
		systemctl enable "$SERVICE"
		;;
	status)
		systemctl status "$SERVICE.service"
		;;
	is-active)
		systemctl is-active "$SERVICE"
		;;
	logs)
		journalctl -u "$SERVICE" -f
		;;
	edit)
		edit_service_file
		;;
	deploy)
		deploy_service "$2"
		;;
	*)
		usage
		;;
esac
