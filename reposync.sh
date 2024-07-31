#!/bin/bash

# Source the configuration file
CONFIG_FILE="/etc/reposync/reposync.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Function to extract file links
extract_links() {
    wget -q -O - "$URL" | \
    grep -oP '(?<=<a href=")[^"]*(?=")' | \
    grep -vE 'Parent Directory|/$|\?C=N;O=D|\?C=M;O=A|\?C=S;O=A|\?C=D;O=A' > "$OUTPUT_FILE"
}

# Function to download files in parallel with logging
download_files() {
    mkdir -p "$DOWNLOAD_DIR" "$LOG_DIR"
    i=0
    cat "$OUTPUT_FILE" | while read -r file; do
        {
            echo "Start time: $(date)" > "$LOG_DIR/wget_$i.log"
            wget -P "$DOWNLOAD_DIR" "$URL/$file" >> "$LOG_DIR/wget_$i.log" 2>&1
            echo "End time: $(date)" >> "$LOG_DIR/wget_$i.log"
        } &
        ((i++))
    done
    wait
    rm "$OUTPUT_FILE"
}

# Function to sync repositories in parallel with logging
sync_repositories() {
    i=0
    for key in "${!RSYNC_MIRRORS[@]}"; do
        {
            IFS=' ' read -r -a mirror <<< "${RSYNC_MIRRORS[$key]}"
            log_file="$LOG_DIR/reposync_$key.log"
            echo "Start time: $(date)" > "$log_file"
            if [[ -f $EXCLUDE_FILE ]]; then
                rsync --chown=www-data:www-data \
                      --archive \
                      --links \
                      --mkpath \
                      --safe-links \
                      --hard-links \
                      --progress \
                      --delete-after \
                      --exclude-from="$EXCLUDE_FILE" \
                      "${mirror[0]}" "${mirror[1]}" >> "$log_file" 2>&1
            else
                rsync --chown=www-data:www-data \
                      --archive \
                      --links \
                      --mkpath \
                      --safe-links \
                      --hard-links \
                      --progress \
                      --delete-after \
                      "${mirror[0]}" "${mirror[1]}" >> "$log_file" 2>&1
            fi
            echo "End time: $(date)" >> "$log_file"
        } &
        ((i++))
    done
    wait
}

# Function to stop script and terminate background processes
stop_script() {
    echo "Stopping script and terminating background processes..."

    # Terminate wget processes
    pkill -f "wget -P $DOWNLOAD_DIR"

    # Terminate rsync processes
    pkill -f "rsync --recursive --times --links --safe-links --hard-links --progress --delete --delete-after"

    echo "Background processes terminated."
    exit 1
}

display_status() {
    echo "Displaying status of background processes..."

    # Check wget processes
    echo "wget processes:"
    pgrep -af "wget -P $DOWNLOAD_DIR"

    # Check rsync processes
    echo "rsync processes:"
    echo -e "\n"
    for key in "${!RSYNC_MIRRORS[@]}"; do
        log_file="$LOG_DIR/reposync_$key.log"
        if [[ -f "$log_file" ]]; then
            start_time=$(grep "Start time" "$log_file")
            end_time=$(grep "End time" "$log_file")
            if [[ -z "$end_time" ]]; then
                printf "sync %-20s started at %-40s and is still running...\n" "$key" "$(echo $start_time | cut -d' ' -f3-)"
            else
                printf "sync %-20s started at %-40s and finished at %-30s\n" "$key" "$(echo $start_time | cut -d' ' -f3-)" "$(echo $end_time | cut -d' ' -f3-)"
            fi
        fi
    done
    echo -e "\n"
    echo "Status display completed."
}

# Function to list and view log files
log() {
    echo "Listing log files..."
    log_files=("$LOG_DIR"/*.log)
    if [[ ${#log_files[@]} -eq 0 ]]; then
        echo "No log files found."
        return
    fi

    for i in "${!log_files[@]}"; do
        echo "$((i+1)). ${log_files[$i]}"
    done

    read -p "Enter the number of the log file to view: " log_number
    if [[ $log_number -gt 0 && $log_number -le ${#log_files[@]} ]]; then
        tail -f "${log_files[$((log_number-1))]}"
    else
        echo "Invalid selection."
    fi
}

# Function to handle command-line arguments
handle_arguments() {
    case "$1" in
        start)
            echo "Starting script..."
            main
            ;;
        stop)
            stop_script
            ;;
        status)
            display_status
            ;;
        log)
            log
            ;;
        *)
            echo "Usage: $0 {start|stop|status|log}"
            exit 1
            ;;
    esac
}

# Main procedure
main() {
    mkdir -p "$LOG_DIR"
    extract_links
    download_files &
    sync_repositories &
}

# Handle command-line arguments
if [[ $# -eq 0 ]]; then
    echo "No arguments supplied. Usage: $0 {start|stop|status|log}"
    exit 1
fi

handle_arguments "$1"