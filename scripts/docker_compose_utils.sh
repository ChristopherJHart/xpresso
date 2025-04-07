#!/usr/bin/env bash

# Function to detect and return the appropriate Docker Compose command
get_docker_compose_cmd() {
    # Check if the new 'docker compose' command is available
    if docker compose version &>/dev/null; then
        echo "docker compose"
    else
        # Fall back to the old 'docker-compose' command
        echo "docker-compose"
    fi
}

# Export the function so it's available in sourced scripts
export -f get_docker_compose_cmd

# If this script is executed directly rather than sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Output the appropriate command
    get_docker_compose_cmd
fi
