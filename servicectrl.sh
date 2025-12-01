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
	echo "Usage: $0 {start|stop|restart}"
	exit 1
}

if [ $# -ne 1 ]; then
	usage
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
	*)
		usage
		;;
esac
