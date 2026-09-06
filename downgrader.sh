#!/bin/bash
set -Eeuo pipefail

# =================Game Specific Variables======================
display_name="Skyrim Special Edition"
game_folder_name="Skyrim Special Edition"
app_id="489830"

versions=(
    "1.5.97" "1.6.640" "1.6.1170"
)
notes=(
    "The pre-anniversary update" "Commonly used version" "Version before the latest update"
)
depot_ids=(
    "489831" "489832" "489833"
)
manifest_ids=( 
    "7848722008564294070 8702665189575304780 2289561010626853674"
    "3660787314279169352 2756691988703496654 5291801952219815735"
    "8442952117333549665 8042843504692938467 1914580699073641964"
)
# ==============================================================

if [[ $EUID -eq 0 ]]; then
    echo "Do NOT run this script as root"
    exit 1
fi

# Find users game installation
game_path=""
downgrader_working_dir=""

# Method 1: Read libraryfolders.vdf
library_file="$HOME/.steam/root/steamapps/libraryfolders.vdf"
if [[ -f "$library_file" ]]; then
    mapfile -t library_paths < <(grep -oP '"path"\s+"\K[^"]+' "$library_file")

    for library in "${library_paths[@]}"; do
        candidate="$library/steamapps/common/$game_folder_name"
        candidate_appmanifest="$library/steamapps/appmanifest_$app_id.acf"
        if [[ -d "$candidate" && -f "$candidate_appmanifest" ]]; then
                game_path="$candidate"
                downgrader_working_dir="$library/steamapps/common/steam_downgrader"
            break
        fi
    done
fi
if [[ -z "$game_path" ]]; then
    echo "Didnt find steam library."
    # TODO check if .steam/root method works with flatpak steam
fi

#Update user on game found
if [[ -n "$game_path" ]]; then
    echo "Found game installation at: $game_path"
else
    echo "Could not find game installation"
    exit 1
fi

downgrade_game() {
    # Warn user about downgrading
    echo "
Warning: This script will replace your $display_name installation with the selected downgraded version
This will remove any mods installed directly into the game folder. Mods managed by a mod manager will generally not be removed, but may need to be redeployed
A backup of your original game folder will be created automatically for safety
This script will download a full new copy of $display_name, this may take some time and will require sufficient free space in your Steam library drive for both (it can be reclaimed afterwards)
"

    read -r -p "Continue? [y/N] " answer
    if [[ ! "$answer" =~ ^([Yy]|[Yy][Ee][Ss])$ ]]; then
        echo "Cancelled"
        exit 0
    fi

    # User choose version
    echo "Available versions:"
    for i in "${!versions[@]}"; do
        echo "[$((i + 1))] ${versions[$i]}          ${notes[$i]}"
    done

    read -r -p "Choose a version [1-${#versions[@]}]: " version_choice

    if [[ ! "$version_choice" =~ ^[0-9]+$ ]] ||
    (( version_choice < 1 || version_choice > ${#versions[@]} )); then
        echo "Invalid choice"
        exit 1
    fi

    version_index=$((version_choice - 1))

    # Download steamCMD from valve
    steamCMD_url="https://client-update.steamstatic.com/installer/steamcmd_linux.tar.gz"
    steamCMD_sha="cebf0046bfd08cf45da6bc094ae47aa39ebf4155e5ede41373b579b8f1071e7c" # SHA found from steam flathub package. It has been stable for >8 years, might one day change

    mkdir -p "$downgrader_working_dir/steamCMD" && cd "$downgrader_working_dir/steamCMD"

    curl -fsSL "$steamCMD_url" -o steamcmd_linux.tar.gz

    echo "$steamCMD_sha  steamcmd_linux.tar.gz" | sha256sum --check

    tar zxf steamcmd_linux.tar.gz
    rm steamcmd_linux.tar.gz

    # check steamCMD dependencies
    missing="$(ldd steamCMD/linux32/steamcmd 2>&1 | grep "not found" || true)"

    if [[ -n "$missing" ]]; then
        echo "SteamCMD is missing required libraries:"
        echo "$missing"
        exit 1
    fi

    # Authenticate steamCMD
    echo "Enter your steam username (for use of valve's steamCMD): "
    read -r steam_username
    "$downgrader_working_dir"/steamCMD/steamcmd.sh "+login" "$steam_username" "+quit"

    # Download Depots
    steamcmd_args=("+login" "$steam_username")
    read -ra manifests <<< "${manifest_ids[$version_index]}"
    for i in "${!depot_ids[@]}"; do
        steamcmd_args+=(
            "+download_depot"
            "$app_id"
            "${depot_ids[$i]}"
            "${manifests[$i]}"
        )
    done
    steamcmd_args+=("+quit")

    "$downgrader_working_dir"/steamCMD/steamcmd.sh "${steamcmd_args[@]}" & steamcmd_pid=$! # The previous run authenticated us so that password input not needed now

    # Track download progress by watching filesize
    download_progress_watch_dir="$downgrader_working_dir/steamCMD/linux32/steamapps/content/app_$app_id"
    while kill -0 "$steamcmd_pid" 2>/dev/null; do
        if [[ -d "$download_progress_watch_dir" ]]; then
            size="$(du -sh "$download_progress_watch_dir" 2>/dev/null | cut -f1 || true)"
            echo "Download progress: ${size:-unknown}"
        fi
        sleep 5
    done
    wait "$steamcmd_pid"

    # check download succeeded
    for i in "${!depot_ids[@]}"; do
        depot_location="$downgrader_working_dir/steamCMD/linux32/steamapps/content/app_$app_id/depot_${depot_ids[$i]}"

        if [[ ! -d "$depot_location" ]]; then
            echo "Download failed: depot ${depot_ids[$i]} was not downloaded."
            exit 1
        fi
        if ! find "$depot_location" -type f -print -quit | grep -q .; then
            echo "Download failed: depot ${depot_ids[$i]} is empty."
            exit 1
        fi
    done

    # Make backup
    backup_dir="$downgrader_working_dir/${game_folder_name}-backup-$(date +%Y-%m-%d_%H-%M-%S)"
    mkdir "$backup_dir"
    if mv "$game_path" "$backup_dir"; then
        echo "Game installation backed up successfully"
    else
        echo "Failed to create backup"
        echo "The original game installation has not been modified"
        exit 1
    fi

    merge_depot() {
        local depot="$1"
        local destination="$2"
        local item
        local name
        for item in "$depot"/* "$depot"/.[!.]* "$depot"/..?*; do
            [[ -e "$item" ]] || continue
            name=$(basename "$item")
            if [[ -d "$item" && -d "$destination/$name" ]]; then
                merge_depot "$item" "$destination/$name"
            else
                mv -f "$item" "$destination/$name"
            fi
        done
    }

    mkdir -p "$game_path"
    for i in "${!depot_ids[@]}"; do
        depot_location="$downgrader_working_dir/steamCMD/linux32/steamapps/content/app_$app_id/depot_${depot_ids[$i]}"

        if ! merge_depot "$depot_location" "$game_path"; then
            echo "Failed to downgrade game"
            do_restore_backup "$backup_dir"
        fi
    done
    echo "Game installation downgraded successfully"
    echo "
To prevent Steam from automatically updating this game in the future, it is recommended 
to make appmanifest_$app_id.acf read-only in the Steam library's steamapps folder

For example:
    chmod a-w \"$library/appmanifest_$app_id.acf\"
"

    # Clean up steamCMD mess
    rm -rf "$downgrader_working_dir/steamCMD"
}

choose_backup_folder() {
    mapfile -t backups < <(
        find "$downgrader_working_dir" -maxdepth 1 -type d -name "${game_folder_name}-backup-*" -print | sort)

    if [[ "${#backups[@]}" -eq 0 ]]; then
        echo "No backups found."
        exit 1
    fi

    if [[ "${#backups[@]}" -eq 1 ]]; then
        backup_dir="${backups[0]}"
    else
        echo "Multiple backups found:"

        for i in "${!backups[@]}"; do
            echo "[$((i + 1))] ${backups[$i]}"
        done

        read -r -p "Choose a backup [1-${#backups[@]}]: " backup_choice

        if [[ ! "$backup_choice" =~ ^[0-9]+$ ]] ||
           (( backup_choice < 1 || backup_choice > ${#backups[@]} )); then
            echo "Invalid choice."
            exit 1
        fi

        backup_dir="${backups[$((backup_choice - 1))]}"
    fi
}

do_restore_backup() {
    local backup_dir="$1"
    rm -rf "$game_path"

    if mv "$backup_dir/$game_folder_name" "$game_path"; then
        echo "Backup restored successfully."
        rmdir "$backup_dir"
    else
        echo "Failed to restore backup."
        exit 1
    fi
}

user_restore_backup() {
    choose_backup_folder

    if [[ ! -d "$backup_dir/$game_folder_name" ]]; then
        echo "Backup is missing the $game_folder_name installation."
        exit 1
    fi

    echo "Selected backup:"
    echo "$backup_dir"
    read -r -p "Restore this backup? [y/N] " answer

    if [[ ! "$answer" =~ ^([Yy]|[Yy][Ee][Ss])$ ]]; then
        echo "Cancelled."
        exit 0
    fi

    do_restore_backup "$backup_dir"
}

remove_backup() {
    choose_backup_folder

    echo "Selected backup:"
    echo "$backup_dir"

    read -r -p "Remove this backup? [y/N] " answer

    if [[ ! "$answer" =~ ^([Yy]|[Yy][Ee][Ss])$ ]]; then
        echo "Cancelled"
        exit 0
    fi
    rm -rf "$backup_dir"
    echo "Backup removed"
}

# Function dispatch based on user's chosen operation
case "${1:-}" in
    --restore-backup)
        user_restore_backup
        ;;
    --remove-backup)
        remove_backup
        ;;
    "")
        downgrade_game
        ;;
    *)
        echo "Unknown argument: $1"
        echo "Usage:"
        echo "  $0"
        echo "  $0 --restore-backup"
        echo "  $0 --remove-backup"
        exit 1
        ;;
esac
# Clean up empty working directory
rmdir "$downgrader_working_dir" 2>/dev/null