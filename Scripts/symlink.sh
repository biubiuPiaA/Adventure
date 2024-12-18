#!/bin/bash

# n0tE
# Create new link → sudo ./symlink.sh -f file.py -n myscript
# Update exist link → sudo ./symlink.sh -f new_file.py -n myscript -u


# Check if the script is run with sudo
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root using sudo."
    exit 1
fi

# Initialize variables
file_path=""
global_name=""
update_mode=false

# Parse command-line arguments
while getopts "f:n:u" opt; do
    case $opt in
        f) file_path=$OPTARG ;;
        n) global_name=$OPTARG ;;
        u) update_mode=true ;;
        *) 
            echo "Usage: $0 -f <file_name> -n <global_name> [-u]"
            exit 1
            ;;
    esac
done

# Check if both -f and -n are provided
if [ -z "$file_path" ] || [ -z "$global_name" ]; then
    echo "Error: Both -f (file path) and -n (global name) are required."
    echo "Usage: $0 -f <file_name> -n <global_name> [-u]"
    exit 1
fi

# Automatically prepend $(pwd)/ if the file path is not absolute
if [[ "$file_path" != /* ]]; then
    file_path="$(pwd)/$file_path"
fi

# Resolve the actual path and check if the file exists
resolved_path=$(eval echo "$file_path")

if [ ! -f "$resolved_path" ]; then
    echo "Error: File '$resolved_path' does not exist."
    exit 1
fi

# Define the link path
link_path="/usr/local/bin/$global_name"

# Handle update mode
if $update_mode; then
    if [ -L "$link_path" ]; then
        # Update the existing symbolic link
        ln -sf "$resolved_path" "$link_path"
        if [ $? -eq 0 ]; then
            echo "Symbolic link updated successfully."
            echo "The global name '$global_name' now points to '$resolved_path'."
        else
            echo "Error: Failed to update symbolic link."
            exit 1
        fi
    else
        echo "Error: The global name '$global_name' does not exist. Use the -n flag to create a new link."
        exit 1
    fi
else
    # Check if the link already exists
    if [ -e "$link_path" ]; then
        echo "Error: The global name '$global_name' already exists. Use the -u flag to update it."
        exit 1
    fi

    # Create the new symbolic link
    ln -s "$resolved_path" "$link_path"
    if [ $? -eq 0 ]; then
        echo "Symbolic link created successfully."
        echo "You can now use '$global_name' to call the file globally."
    else
        echo "Error: Failed to create symbolic link."
        exit 1
    fi
fi
