#/bin/bash
PACKAGES_FILE="$HOME/.config/dotfiles/packages.csv"
PM=
DISTRO=
SYSTEM_TYPE=
INSTALLCOMMAND=

# Read system type from the first argument or default to "headless"
if [ -n "$1" ]; then
    SYSTEM_TYPE="$1"
else
    echo "No system type specified. Defaulting to 'headless'."
    echo "Usage: $0 [system_type]\n"
    SYSTEM_TYPE="headless"
fi

# Attempt to detect the distro
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID_LIKE" in
        *debian*)
            PM="apt"
            DISTRO="debian"
            ;;
        *alpine*)
            PM="apk"
            DISTRO="alpine"
            ;;
        *fedora*|*rhel*)
            PM="dnf"
            DISTRO="fedora"
            ;;
        *arch*)
            DISTRO="arch"
            # PM="pacman"   # never set PM to pacman directly, use yay instead
            ;;
        *)
            echo "Unsupported distribution family: $ID_LIKE"
            exit 1
            ;;
    esac
else
    echo "Could not detect the distribution. Please set the PM variable manually."
    exit 1
fi

INSTALLCOMMAND="$PM install -y"

# In Arch Linux, install yay if not already installed
if [ "$DISTRO" = "arch" ]; then
    if ! command -v yay &> /dev/null; then
        echo "Installing yay for Arch Linux..."
        sudo pacman -S --noconfirm base-devel git
        local builddir
        builddir=$(mktemp -d)
        ( # Start a subshell to avoid cd side effects
            cd "$build_dir" || exit 1
            git clone https://aur.archlinux.org/yay.git
            cd yay || exit 1
            makepkg -si --noconfirm
        ) # Subshell ends, cd is reverted
        rm -rf "$builddir"
    fi
    PM="yay"
    INSTALLCOMMAND="yay -S --noconfirm --needed"
fi


# Check if the package manager is supported
if ! command -v "$PM" > /dev/null 2>&1; then
    echo "Package manager $PM is not installed or not supported."
    exit 1
fi

# Prepare to install packages
if [ "$PM" = "apt" ]; then
    sudo apt update

elif [ "$PM" = "apk" ]; then
    sudo apk update
elif [ "$PM" = "dnf" ]; then
    # dnf automatically checks for updates when installing packages
elif [ "$PM" = "yay" ]; then
    yay -Sy
else
    echo "Unsupported package manager: $PM"
    exit 1
fi

# Check if the packages file is readable
if [ ! -r "$PACKAGES_FILE" ]; then
    echo "Packages file $PACKAGES_FILE is not readable."
    exit 1
fi

if tail -n +2 "$PACKAGES_FILE" | cut -d, -f2 | grep -q -x -e '' -e 'default'; then
    echo "Invalid package file format: Second column (package manager) cannot be empty or 'default'. Use '_default' or a specific package manager (e.g., apt, dnf, yay)."
    exit 1
fi

# Preprocess once and store in a temp file
tempfile=$(mktemp)

# Filter for package manager and system type
# Keep the installation order by sorting based on added row number column
# This will ensure that dependencies are installed first
tail -n +2 "$PACKAGES_FILE" \
| grep -E "^([^,]*,){3}(all|"$SYSTEM_TYPE")(,|$)" \
| grep -E "^([^,]*,)?(_default|"$PM")(,|$)" \
| awk '{print NR","$0}' \
| sort -t, -k3,3r \
| awk -F, '!seen[$2]++' \
| sort -t, -k1,1n \
| cut -d, -f2- > "$tempfile"

# Count total lines (n)
total=$(wc -l < "$tempfile")
count=0

echo "Total packages to install: $total"

github_install() {
    local repo="$1"
    local name="$2"
    echo "Installing $name from GitHub repository: $repo"
    "$HOME/bin/get_latest_git_release.sh" "$repo" "$name" || {
        echo -e "\033[31mFailed to install $name from GitHub. Continuing with next package.\033[0m"
        return 1
    }
}

# Loop install packages with counter
while IFS=, read -r name pkg_man pkg stype notes github; do
    count=$((count + 1))
    echo "Processing ($count of $total): $name"
    # Skip if the command exists
    if command -v "$name" > /dev/null 2>&1; then
        echo "${name} is already installed. Skipping."
        continue
    fi
    eval "sudo $INSTALLCOMMAND $pkg" || {
        if [ -n "$github" ]; then
            github_install "$github" "$name"
        else
            echo -e "\033[31mFailed to install $pkg using $PM. Continuing with next package.\033[0m"
        fi
        continue
    }
done < "$tempfile"


# Clean up
rm "$tempfile"

# Clean package manager cache
if [ "$PM" = "apt" ]; then
    sudo apt clean
elif [ "$PM" = "apk" ]; then
    sudo apk cache clean
elif [ "$PM" = "pacman" ]; then
    sudo pacman -Scc --noconfirm
elif [ "$PM" = "dnf" ]; then
    sudo dnf clean all
elif [ "$PM" = "yay" ]; then
    sudo yay -Rns $(pacman -Qdtq)
else
    echo "Unsupported package manager: $PM"
    exit 1
fi

