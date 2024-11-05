#!/bin/bash

# Retrieve API token from Keychain
API_TOKEN=$(security find-generic-password -a "markolisica" -s "Fleet API Token" -w)

# Use a team that doesn't have Fleet-maintained apps added to it,
# so you always can see all available apps and latest versions
TEAM_ID=0

# Function to fetch maintained apps
fetch_maintained_apps() {
    local url="https://dogfood.fleetdm.com/api/v1/fleet/software/fleet_maintained_apps?team_id=$TEAM_ID"
    
    response=$(curl -s -H "Authorization: Bearer $API_TOKEN" "$url")
    echo "$response" | jq -r '.fleet_maintained_apps[] | "\(.id),\(.name),\(.version),\(.platform)"'
}

# Function to fetch app details
fetch_app_details() {
    local app_id="$1"
    local url="https://dogfood.fleetdm.com/api/v1/fleet/software/fleet_maintained_apps/$app_id"
    
    response=$(curl -s -H "Authorization: Bearer $API_TOKEN" "$url")
    echo "$response" | jq -r '.fleet_maintained_app'
}

# Function to format the script
format_script() {
    local script="$1"
    formatted_script=$(echo "$script" | sed 's/\\n/\n/g; s/\\'\''/'\''/g; s/\\"/"/g')
    echo "$formatted_script"
}

# Function to write scripts to the /lib/scripts directory
write_script() {
    local script_content="$1"
    local script_name="$2"
    local script_path="../../scripts/$script_name"  # Adjusted path for script files
    
    echo "$script_content" > "$script_path"
    
    echo "$script_path"
}


# Function to generate YAML
generate_yaml() {
    local app_details="$1"
    local app_name=$(echo "$app_details" | jq -r '.name' | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g')
    
    if [ -z "$app_name" ]; then
        echo "Error: App name is empty. Cannot generate YAML."
        return
    fi

    local yaml_file="$app_name.package.yml"

    # Extracting details
    local url=$(echo "$app_details" | jq -r '.url')
    local version=$(echo "$app_details" | jq -r '.version')
    local install_script=$(format_script "$(echo "$app_details" | jq -r '.install_script')")
    local uninstall_script=$(format_script "$(echo "$app_details" | jq -r '.uninstall_script')")

    # Write install and uninstall scripts
    local install_script_path=$(write_script "$install_script" "${app_name}-install.sh")
    local uninstall_script_path=$(write_script "$uninstall_script" "${app_name}-uninstall.sh")

    # Prepare YAML content
    local yaml_content=$(cat <<EOF
url: "https://example.com/dl/package/install-22.0.0.pkg"
version: $version
install_script:
  path: $install_script_path
uninstall_script:
  path: $uninstall_script_path
EOF
)

    # Check if the YAML file already exists
    if [ -f "$yaml_file" ]; then
        # Compare content, ignoring self_service field if present
        existing_content=$(sed '/self_service/d' "$yaml_file")
        new_content=$(sed '/self_service/d' <(echo "$yaml_content"))

        if [ "$existing_content" == "$new_content" ]; then
            echo "No changes to $yaml_file. Skipping..."
            return
        fi
    fi

    # Write to YAML file
    echo "$yaml_content" > "$yaml_file"
    echo "Generated YAML file: $yaml_file"
}

# Function to commit and open a PR
commit_and_open_pr() {
    local branch_name="update-yaml-$(date +%Y%m%d%H%M%S)"
    git checkout -b "$branch_name"
    
    # Add all generated YAML files in the current directory
    git add *.package.yml

    # Check if there are changes to commit
    if git diff --cached --quiet; then
        echo "No changes to commit."
        git checkout main
        git branch -D "$branch_name"
        return
    fi

    # Commit changes
    git commit -m "Update Fleet-maintained apps"

    # Push changes to the remote repository
    git push origin "$branch_name"

    # Open a pull request
    gh pr create --base main --head "$branch_name" --title "Update Fleet-maintained apps" --body "This PR updates the Fleet-maintained apps."
}

# Main script execution
OPEN_PR=false

# Check for --open-pr flag
for arg in "$@"; do
    if [[ "$arg" == "--open-pr" ]]; then
        OPEN_PR=true
        break
    fi
done

echo "Fetching maintained apps..."
apps=$(fetch_maintained_apps "$API_TOKEN")

echo "Available Apps:"
declare -A valid_apps
while IFS=, read -r id name version platform; do
    valid_apps["$id"]="$name"
    echo "ID: $id, Name: $name, Version: $version, Platform: $platform"
done <<< "$apps"

read -p "Enter the app IDs you want to transform to YAML files (comma-separated): " selected_ids

IFS=',' read -ra ids <<< "$selected_ids"
for app_id in "${ids[@]}"; do
    app_id=$(echo "$app_id" | xargs) # Trim whitespace

    # Check if the app ID exists in the valid_apps array
    if [[ -z "${valid_apps[$app_id]}" ]]; then
        echo "Warning: App ID $app_id does not exist. Skipping..."
        continue
    fi

    app_details=$(fetch_app_details "$app_id")

    # Check if app_details is empty
    if [ -z "$app_details" ]; then
        echo "Error: Failed to fetch details for app ID $app_id."
        continue
    fi

    generate_yaml "$app_details"
done

# Call the function to commit and open a PR after generating YAML files
if [[ "$OPEN_PR" == true ]]; then
    commit_and_open_pr
fi
