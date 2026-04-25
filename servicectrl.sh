#!/bin/bash
: '=======================================================
Service Control

Starts, stops, or restarts the app service.
=========================================================='

PYPROJECT="pyproject.toml"

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

usage() {
	echo "Usage: $0 {start|stop|restart|reload|disable|enable|status|logs|help}"
	exit 1
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
	*)
		usage
		;;
esac
