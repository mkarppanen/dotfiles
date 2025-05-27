#!/bin/bash

# This script fetches the latest release of a GitHub repository and installs it.
# Usage: ./executable_get_latest_git_release.sh <repo_owner>/<repo_name>

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <repo_owner>/<repo_name> [CMD_NAME] [ARCH]"
    echo "Example: $0 user/repo"
    exit 1
fi

# Split the input argument into repository owner and name
REPO_OWNER="${1%%/*}"
REPO_NAME="${1##*/}"
CMD_NAME="${2:-$REPO_NAME}"  # Default command name is the repository name
ARCH="${3:-}"  # Optional architecture argument, defaults to empty

# Ensure jq and wget are installed
if ! command -v jq &> /dev/null || ! command -v wget &> /dev/null; then
    echo "Error: jq and wget are required but not installed."
    echo "Please install them using your package manager."
    exit 1
fi

# Determine system architecture if not explicitly set
if [[ -z "$ARCH" ]]; then
    if [[ "$(uname -m)" == "x86_64" ]]; then
        ARCH="amd64"
    elif [[ "$(uname -m)" == "aarch64" ]]; then
        ARCH="arm64"
    elif [[ "$(uname -m)" == "i386" || "$(uname -m)" == "i686" ]]; then
        ARCH="386"
    else
        echo "Unsupported architecture: $(uname -m). Please set ARCH manually."
        exit 1
    fi
fi
echo "Using architecture: $ARCH"

# API endpoint for the latest release
API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"

echo "Fetching latest release information for ${REPO_OWNER}/${REPO_NAME}..."

# Fetch release information and parse with jq
response=$(curl -s "$API_URL")

# Check if curl command was successful and if response is valid JSON
if [ $? -ne 0 ]; then
    echo "Error: Failed to fetch release information from GitHub API."
    exit 1
fi

if ! echo "$response" | jq -e . > /dev/null; then
    echo "Error: Invalid JSON response received from GitHub API."
    echo "Response: $response"
    exit 1
fi

# Extract the tag name and download URL for the specific architecture
LATEST_TAG=$(echo "$response" | jq -r '.tag_name')
DOWNLOAD_URL=$(echo "$response" | jq -r ".assets[] | select(.name | contains(\"linux-${ARCH}\")) | .browser_download_url")

if [[ -z "$LATEST_TAG" || -z "$DOWNLOAD_URL" ]]; then
    echo "Error: Could not find the latest tag or download URL for ${REPO_OWNER}/${REPO_NAME} with architecture ${ARCH}."
    echo "Response from API:"
    # echo "$response" | jq . # Pretty print the response for debugging
    exit 1
fi

INSTALL_DIR="$HOME/.local/bin"
TEMP_DIR=$(mktemp -d)


echo "Latest version: $LATEST_TAG"
echo "Download URL: $DOWNLOAD_URL"
echo "Temporary download directory: $TEMP_DIR"
echo "Installation directory: $INSTALL_DIR"

# Create install directory if it doesn't exist
mkdir -p "$INSTALL_DIR"

# FILENAME is derived from the download URL
FILENAME=${DOWNLOAD_URL##*/}

# Download the file
echo "Downloading $FILENAME..."
if ! wget -q --show-progress -O "${TEMP_DIR}/${FILENAME}" "$DOWNLOAD_URL"; then
    echo "Error: Failed to download $FILENAME."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# If the file is a tarball, extract it
# If the file is not a tarball, make it executable and rename it
if [[ "$FILENAME" != *.tar.gz ]]; then
    echo "Downloaded file is not a tarball, making it executable..."
    chmod +x "${TEMP_DIR}/${FILENAME}"
    mv "${TEMP_DIR}/${FILENAME}" "$TEMP_DIR/$CMD_NAME"
elif [[ "$FILENAME" == *.tar.gz ]]; then
    echo "Downloaded file is a tarball, extracting..."
    if ! tar -xzf "${TEMP_DIR}/${FILENAME}" -C "$TEMP_DIR"; then
        echo "Error: Failed to extract binary."
        rm -rf "$TEMP_DIR"
        exit 1
    fi
fi

# Move the binary to the install directory
echo "Moving to $INSTALL_DIR..."
if ! mv "${TEMP_DIR}"/"$CMD_NAME" "$INSTALL_DIR/"; then
    echo "Error: Failed to move $CMD_NAME binary."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Clean up temporary directory
echo "Cleaning up temporary files..."
rm -rf "$TEMP_DIR"

echo "$CMD_NAME version $LATEST_TAG installed successfully!"