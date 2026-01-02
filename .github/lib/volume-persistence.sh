#!/bin/bash
# ========================================
# Atlas Volume Persistence Helper Library
# ========================================
# Questa libreria fornisce funzioni per gestire la persistenza
# dei volumi nei servizi Atlas (sia ufficiali che custom).
#
# USAGE:
#   source .github/lib/volume-persistence.sh
#   atlas_restore_volume "/path/to/volume" "data/my-service"
#   atlas_backup_volume "/path/to/volume" "data/my-service"
#
# ========================================

set -e

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ========================================
# FUNCTION: atlas_restore_volume
# ========================================
# Ripristina un volume dalla directory data/ del repository
#
# ARGS:
#   $1 - Volume path (es. /tmp/postgres-data)
#   $2 - Repo data path (es. data/postgresql)
#   $3 - Owner UID:GID (optional, es. 999:999)
#
# EXAMPLE:
#   atlas_restore_volume "/tmp/postgres-data" "data/postgresql" "999:999"
#
atlas_restore_volume() {
  local volume_path="$1"
  local repo_data_path="$2"
  local owner="${3:-}"
  
  echo -e "${BLUE}📦 Restoring volume: $volume_path${NC}"
  
  # Validate inputs
  if [ -z "$volume_path" ] || [ -z "$repo_data_path" ]; then
    echo -e "${RED}❌ Error: volume_path and repo_data_path are required${NC}"
    return 1
  fi
  
  # Create volume directory
  echo "   Creating volume directory..."
  sudo mkdir -p "$volume_path"
  
  # Check if repo data exists
  if [ -d "$repo_data_path" ] && [ "$(ls -A "$repo_data_path" 2>/dev/null)" ]; then
    echo -e "${GREEN}   ✅ Found existing data in $repo_data_path${NC}"
    
    # Check for compressed archive
    if [ -f "$repo_data_path/volume-data.tar.gz" ]; then
      echo "   📦 Found compressed archive, extracting..."
      
      # Extract archive directly to volume path
      sudo tar -xzf "$repo_data_path/volume-data.tar.gz" -C "$volume_path" 2>/dev/null || {
        echo -e "${YELLOW}   ⚠️  Failed to extract archive, trying direct copy...${NC}"
        sudo rsync -av --delete "$repo_data_path/" "$volume_path/"
      }
    else
      echo "   Restoring files (legacy uncompressed format)..."
      sudo rsync -av --delete "$repo_data_path/" "$volume_path/"
    fi
    
    # Set ownership if specified
    if [ -n "$owner" ]; then
      echo "   Setting ownership to $owner..."
      sudo chown -R "$owner" "$volume_path"
    fi
    
    echo -e "${GREEN}   ✅ Volume restored successfully${NC}"
  else
    echo -e "${YELLOW}   ⚠️  No previous data found in $repo_data_path${NC}"
    echo -e "${YELLOW}   Starting with empty volume${NC}"
  fi
  
  echo ""
}

# ========================================
# FUNCTION: atlas_backup_volume
# ========================================
# Esegue il backup di un volume nella directory data/ del repository
#
# ARGS:
#   $1 - Volume path (es. /tmp/postgres-data)
#   $2 - Repo data path (es. data/postgresql)
#   $3 - Container name (optional, per stop prima del backup)
#   $4 - Stop command (optional, default: docker stop)
#
# EXAMPLE:
#   atlas_backup_volume "/tmp/postgres-data" "data/postgresql" "postgres"
#
atlas_backup_volume() {
  local volume_path="$1"
  local repo_data_path="$2"
  local container_name="${3:-}"
  local stop_command="${4:-}"
  
  echo -e "${BLUE}💾 Backing up volume: $volume_path${NC}"
  
  # Validate inputs
  if [ -z "$volume_path" ] || [ -z "$repo_data_path" ]; then
    echo -e "${RED}❌ Error: volume_path and repo_data_path are required${NC}"
    return 1
  fi
  
  # Check if volume exists
  if [ ! -d "$volume_path" ]; then
    echo -e "${YELLOW}   ⚠️  Volume path does not exist: $volume_path${NC}"
    echo -e "${YELLOW}   Skipping backup${NC}"
    return 0
  fi
  
  # Stop container if specified
  if [ -n "$container_name" ]; then
    echo "   Stopping container: $container_name"
    if [ -n "$stop_command" ]; then
      eval "$stop_command" || echo "   Warning: stop command failed"
    else
      docker stop "$container_name" 2>/dev/null || echo "   Warning: container already stopped"
    fi
    sleep 2
  fi
  
  # Create repo data directory
  echo "   Creating backup directory: $repo_data_path"
  mkdir -p "$repo_data_path"
  
  # Remove ALL old content (both compressed and uncompressed)
  echo "   Cleaning old backup data..."
  rm -rf "${repo_data_path:?}/"* 2>/dev/null || true
  
  # Backup data with compression
  echo "   📦 Compressing and backing up files..."
  
  # Create temporary archive with proper permissions
  TEMP_ARCHIVE="/tmp/atlas-backup-$$.tar.gz"
  sudo rm -f "$TEMP_ARCHIVE" 2>/dev/null || true
  
  # Use tar with --ignore-failed-read to handle files that change during backup
  if sudo tar --ignore-failed-read -czf "$TEMP_ARCHIVE" -C "$volume_path" . 2>&1 | grep -v "file changed as we read it" || true; then
    # Move archive to repo (preserva sudo per il mv)
    sudo mv "$TEMP_ARCHIVE" "$repo_data_path/volume-data.tar.gz"
    sudo chmod 644 "$repo_data_path/volume-data.tar.gz"
    sudo chown $(whoami):$(whoami) "$repo_data_path/volume-data.tar.gz" 2>/dev/null || true
    
    # Get compressed size
    ARCHIVE_SIZE=$(du -h "$repo_data_path/volume-data.tar.gz" | cut -f1)
    echo -e "${GREEN}   ✅ Archive created: $ARCHIVE_SIZE${NC}"
    
    # Verify archive integrity
    if tar -tzf "$repo_data_path/volume-data.tar.gz" >/dev/null 2>&1; then
      echo -e "${GREEN}   ✅ Archive verified${NC}"
    else
      echo -e "${RED}   ❌ Archive corrupted, using fallback${NC}"
      rm -f "$repo_data_path/volume-data.tar.gz"
      sudo rsync -av --delete "$volume_path/" "$repo_data_path/"
    fi
  else
    echo -e "${YELLOW}   ⚠️  Compression failed, falling back to direct copy${NC}"
    sudo rm -f "$TEMP_ARCHIVE" 2>/dev/null || true
    sudo rsync -av --delete "$volume_path/" "$repo_data_path/"
  fi
  
  # Restart container if it was stopped
  if [ -n "$container_name" ]; then
    echo "   Restarting container: $container_name"
    docker start "$container_name" 2>/dev/null || echo "   Warning: failed to restart container"
  fi
  
  echo -e "${GREEN}   ✅ Volume backed up successfully${NC}"
  echo ""
}

# ========================================
# FUNCTION: atlas_commit_volumes
# ========================================
# Esegue commit e push dei volumi nel repository
#
# ARGS:
#   $1 - Commit message (optional)
#
# EXAMPLE:
#   atlas_commit_volumes "Updated database"
#
atlas_commit_volumes() {
  local commit_message="${1:-Automated volume backup - $(date -Iseconds)}"
  
  echo -e "${BLUE}📤 Committing volumes to repository${NC}"
  
  # Configure git
  git config user.name "Atlas Bot"
  git config user.email "bot@atlas.local"
  
  # Setup Git LFS for compressed archives (auto-tracking)
  echo "   Configuring Git LFS for compressed archives..."
  
  # Ensure .gitattributes exists and tracks volume archives
  if [ ! -f .gitattributes ] || ! grep -q "volume-data.tar.gz" .gitattributes 2>/dev/null; then
    echo "data/**/volume-data.tar.gz filter=lfs diff=lfs merge=lfs -text" >> .gitattributes
    git add .gitattributes
  fi
  
  # Track all existing volume archives with LFS
  find data -name "volume-data.tar.gz" -type f 2>/dev/null | while read -r file; do
    FILE_SIZE=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
    if [ -n "$FILE_SIZE" ] && [ "$FILE_SIZE" -gt 52428800 ]; then  # >50MB
      echo "   📦 Tracking large archive with LFS: $file ($(numfmt --to=iec $FILE_SIZE 2>/dev/null || echo "$FILE_SIZE bytes"))"
      git lfs track "$file" 2>/dev/null || true
    fi
  done
  
  # Add data directory
  git add data/ 2>/dev/null || true
  
  # Check if there are changes
  if git diff --staged --quiet; then
    echo -e "${YELLOW}   ℹ️  No changes to commit${NC}"
    return 0
  fi
  
  # Commit
  echo "   Creating commit..."
  git commit -m "chore(volumes): $commit_message"
  
  # Push with detailed error handling and retry logic
  echo "   Pushing to remote..."
  PUSH_RETRIES=3
  RETRY_COUNT=0
  
  while [ $RETRY_COUNT -lt $PUSH_RETRIES ]; do
    if git push origin main 2>&1 | tee /tmp/git-push.log; then
      echo -e "${GREEN}   ✅ Changes pushed successfully${NC}"
      return 0
    else
      # Check if it's a "fetch first" error (race condition)
      if grep -q "fetch first\|rejected" /tmp/git-push.log 2>/dev/null; then
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $PUSH_RETRIES ]; then
          echo -e "${YELLOW}   ⚠️  Push rejected, attempting pull and retry ($RETRY_COUNT/$PUSH_RETRIES)...${NC}"
          
          # Pull with rebase to integrate remote changes
          if git pull --rebase origin main 2>&1; then
            echo "   ✅ Successfully rebased with remote changes"
            sleep 2  # Small delay before retry
            continue
          else
            echo -e "${YELLOW}   ⚠️  Rebase conflict, trying merge strategy...${NC}"
            git rebase --abort 2>/dev/null || true
            git pull --no-rebase origin main 2>&1 || {
              echo -e "${RED}   ❌ Failed to merge remote changes${NC}"
              break
            }
            sleep 2
            continue
          fi
        fi
      fi
      
      # If we're here, it's a different error or max retries reached
      break
    fi
  done
  
  # Push failed after retries
  echo -e "${RED}   ❌ Push failed after $RETRY_COUNT retries!${NC}"
  echo -e "${YELLOW}   Error details:${NC}"
  cat /tmp/git-push.log || true
  
  # Check if it's a large file issue
  if grep -q "exceeds GitHub's file size limit" /tmp/git-push.log 2>/dev/null; then
    echo ""
    echo -e "${YELLOW}   🔧 Detected large file issue. Attempting Git LFS migration...${NC}"
    
    # Unstage everything
    git reset HEAD~1 --soft
    
    # Force LFS tracking for ALL tar.gz in data/
    echo "data/**/*.tar.gz filter=lfs diff=lfs merge=lfs -text" > .gitattributes
    git add .gitattributes
    
    # Migrate large files to LFS
    git lfs migrate import --include="data/**/*.tar.gz" --everything 2>/dev/null || {
      # If migrate fails, manually track and re-add
      git lfs track "data/**/*.tar.gz"
      git add .gitattributes
      git add data/
    }
    
    # Retry commit and push
    git commit -m "chore(volumes): $commit_message"
    echo "   Retrying push with LFS..."
    if git push origin main 2>&1; then
      echo -e "${GREEN}   ✅ Changes pushed successfully with LFS${NC}"
      return 0
    else
      echo -e "${RED}   ❌ Retry failed${NC}"
    fi
  fi
  
  echo ""
  echo -e "${YELLOW}   Common causes:${NC}"
  echo "   - Missing 'contents: write' permission in workflow"
  echo "   - Branch protection rules preventing push"
  echo "   - GITHUB_TOKEN expired or invalid"
  echo "   - Files too large (Git LFS should be configured)"
  echo ""
  echo -e "${YELLOW}   💡 Tip: Add this to your workflow:${NC}"
  echo "   permissions:"
  echo "     contents: write"
  return 1
  
  echo ""
}

# ========================================
# FUNCTION: atlas_setup_gitattributes
# ========================================
# Configura Git LFS per tipi di file comuni
#
# ARGS:
#   $1 - Preset type (database|media|custom)
#   $2 - Custom patterns file (optional, per preset=custom)
#
# EXAMPLE:
#   atlas_setup_gitattributes "database"
#
atlas_setup_gitattributes() {
  local preset="${1:-general}"
  local custom_file="${2:-}"
  
  echo -e "${BLUE}⚙️  Setting up Git LFS attributes (preset: $preset)${NC}"
  
  local gitattributes_file=".gitattributes"
  
  case "$preset" in
    database)
      cat > "$gitattributes_file" <<EOF
# Database files
data/**/*.db filter=lfs diff=lfs merge=lfs -text
data/**/*.sqlite filter=lfs diff=lfs merge=lfs -text
data/**/*.sql filter=lfs diff=lfs merge=lfs -text
data/**/*.dump filter=lfs diff=lfs merge=lfs -text
data/**/pg_wal/* filter=lfs diff=lfs merge=lfs -text
data/**/base/* filter=lfs diff=lfs merge=lfs -text

# Archives
*.tar.gz filter=lfs diff=lfs merge=lfs -text
*.zip filter=lfs diff=lfs merge=lfs -text
EOF
      ;;
    
    media)
      cat > "$gitattributes_file" <<EOF
# Media files
data/**/*.jpg filter=lfs diff=lfs merge=lfs -text
data/**/*.jpeg filter=lfs diff=lfs merge=lfs -text
data/**/*.png filter=lfs diff=lfs merge=lfs -text
data/**/*.gif filter=lfs diff=lfs merge=lfs -text
data/**/*.mp4 filter=lfs diff=lfs merge=lfs -text
data/**/*.mp3 filter=lfs diff=lfs merge=lfs -text
data/**/*.pdf filter=lfs diff=lfs merge=lfs -text
EOF
      ;;
    
    custom)
      if [ -n "$custom_file" ] && [ -f "$custom_file" ]; then
        cp "$custom_file" "$gitattributes_file"
      else
        echo -e "${RED}   ❌ Custom file not found: $custom_file${NC}"
        return 1
      fi
      ;;
    
    *)
      cat > "$gitattributes_file" <<EOF
# General binary files
data/**/*.bin filter=lfs diff=lfs merge=lfs -text
data/**/*.dat filter=lfs diff=lfs merge=lfs -text
*.tar.gz filter=lfs diff=lfs merge=lfs -text
EOF
      ;;
  esac
  
  echo -e "${GREEN}   ✅ .gitattributes configured${NC}"
  echo ""
}

# ========================================
# FUNCTION: atlas_volume_stats
# ========================================
# Mostra statistiche sui volumi
#
# ARGS:
#   $1 - Volume path
#
# EXAMPLE:
#   atlas_volume_stats "/tmp/postgres-data"
#
atlas_volume_stats() {
  local volume_path="$1"
  local repo_path="${2:-}"
  
  if [ ! -d "$volume_path" ]; then
    echo -e "${YELLOW}Volume path does not exist: $volume_path${NC}"
    return 1
  fi
  
  echo -e "${BLUE}📊 Volume Statistics${NC}"
  echo "   Path: $volume_path"
  echo -n "   Size (uncompressed): "
  du -sh "$volume_path" 2>/dev/null | awk '{print $1}' || echo "unknown"
  echo -n "   Files: "
  find "$volume_path" -type f 2>/dev/null | wc -l | xargs || echo "unknown"
  
  # Show compressed archive size if exists
  if [ -n "$repo_path" ] && [ -f "$repo_path/volume-data.tar.gz" ]; then
    echo -n "   Backup size (compressed): "
    du -sh "$repo_path/volume-data.tar.gz" 2>/dev/null | awk '{print $1}' || echo "unknown"
    
    # Calculate compression ratio
    UNCOMPRESSED=$(du -sb "$volume_path" 2>/dev/null | awk '{print $1}')
    COMPRESSED=$(stat -f%z "$repo_path/volume-data.tar.gz" 2>/dev/null || stat -c%s "$repo_path/volume-data.tar.gz" 2>/dev/null)
    if [ -n "$UNCOMPRESSED" ] && [ -n "$COMPRESSED" ] && [ "$UNCOMPRESSED" -gt 0 ]; then
      RATIO=$(awk "BEGIN {printf \"%.1f\", ($COMPRESSED/$UNCOMPRESSED)*100}")
      echo "   Compression ratio: ${RATIO}%"
    fi
  fi
  
  echo ""
}

# ========================================
# UTILITIES
# ========================================

# Print helper info
atlas_volume_help() {
  cat <<EOF
${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
${GREEN}Atlas Volume Persistence Helper${NC}
${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

Available functions:

  ${GREEN}atlas_restore_volume${NC} <volume_path> <repo_data_path> [owner]
    Restore volume from repository data directory
    
  ${GREEN}atlas_backup_volume${NC} <volume_path> <repo_data_path> [container] [stop_cmd]
    Backup volume to repository data directory
    
  ${GREEN}atlas_commit_volumes${NC} [message]
    Commit and push volumes to repository
    
  ${GREEN}atlas_setup_gitattributes${NC} <preset>
    Setup Git LFS attributes (database|media|general|custom)
    
  ${GREEN}atlas_volume_stats${NC} <volume_path>
    Show volume statistics

Example workflow:
  source .github/lib/volume-persistence.sh
  atlas_restore_volume "/tmp/myapp-data" "data/myapp"
  # ... deploy your service ...
  atlas_backup_volume "/tmp/myapp-data" "data/myapp" "myapp-container"
  atlas_commit_volumes "Updated after deployment"

${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
EOF
}

# Check if sourced or executed
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  atlas_volume_help
fi
