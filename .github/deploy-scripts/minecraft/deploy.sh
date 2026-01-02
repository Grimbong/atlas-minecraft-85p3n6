#!/bin/bash
# ========================================
# Minecraft Server Deployment Script
# ========================================
#
# Features:
# - Automatic Minecraft vanilla server download
# - Configurable via workflow inputs (no JSON needed)
# - Automatic world backup/restore
# - Volume persistence support
#
# Environment Variables:
# - MC_PORT: Server port (default: 25565)
# - MC_VERSION: Minecraft version (default: 1.21.4)
# - JAVA_HEAP: Java heap memory (default: 6G)
# - MC_DATA_DIR: Data directory (default: /tmp/minecraft-data)
# - GATEWAY_IP: Public gateway IP
#
# World Generation:
# - WORLDGEN_TYPE: World type (normal, flat, large_biomes, amplified)
# - WORLDGEN_SEED: Seed for generation (empty = random)
# - WORLDGEN_STRUCTURES: Generate structures (true/false)
#
# Server Settings:
# - MAX_PLAYERS: Maximum players (default: 20)
# - DIFFICULTY: Difficulty level (peaceful, easy, normal, hard)
# - GAMEMODE: Default gamemode (survival, creative, adventure, spectator)
# - PVP: Enable PvP (true/false)
# - VIEW_DISTANCE: View distance in chunks (default: 10)
#
# ========================================

set -e

echo "🚀 Starting Minecraft server deployment..."

# ========================================
# VARIABILI AMBIENTE
# ========================================
MC_PORT="${MC_PORT:-${PUBLIC_PORT:-25565}}"
JAVA_HEAP="${JAVA_HEAP:-6G}"
MC_VERSION="${MC_VERSION:-1.21.4}"  # Default version
MC_DATA_DIR="${MC_DATA_DIR:-/tmp/minecraft-data}"

# ========================================
# SETUP DIRECTORIES
# ========================================
echo "📁 Setting up data directory..."

# Se la directory esiste, assicura permessi corretti
if [ -d "$MC_DATA_DIR" ]; then
  echo "  Fixing permissions on existing directory..."
  sudo chown -R $USER:$USER "$MC_DATA_DIR" 2>/dev/null || true
  chmod -R 755 "$MC_DATA_DIR" 2>/dev/null || true
else
  mkdir -p "$MC_DATA_DIR"
  chmod 755 "$MC_DATA_DIR"
fi

cd "$MC_DATA_DIR"

# Rimuovi file parziali o corrotti da download precedenti
if [ -f server.jar ] && [ ! -s server.jar ]; then
  echo "  Removing incomplete server.jar..."
  rm -f server.jar
fi

# ========================================
# SETUP JAVA
# ========================================
echo "☕ Checking Java..."
java -version || {
  echo "❌ Java not available"
  exit 1
}

# ========================================
# DOWNLOAD SERVER
# ========================================
if [ ! -f server.jar ]; then
  echo "📦 Downloading Minecraft server ${MC_VERSION}..."
  
  # Ottieni hash della versione da Mojang API
  echo "  Fetching version manifest..."
  MANIFEST_URL="https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
  VERSION_URL=$(curl -s "$MANIFEST_URL" | jq -r ".versions[] | select(.id==\"${MC_VERSION}\") | .url")
  
  if [ -z "$VERSION_URL" ] || [ "$VERSION_URL" = "null" ]; then
    echo "  ⚠️  Version ${MC_VERSION} not found, using 1.21.4 fallback"
    SERVER_JAR_URL="https://piston-data.mojang.com/v1/objects/64bb6d763bed0a9f1d632ec347938594144943ed/server.jar"
  else
    echo "  Found version manifest: ${VERSION_URL}"
    SERVER_JAR_URL=$(curl -s "$VERSION_URL" | jq -r '.downloads.server.url')
    echo "  Server JAR URL: ${SERVER_JAR_URL}"
  fi
  
  # Download con gestione errori
  DOWNLOAD_DIR=$(mktemp -d)
  if wget -O "$DOWNLOAD_DIR/server.jar" "$SERVER_JAR_URL" 2>&1; then
    mv "$DOWNLOAD_DIR/server.jar" "$MC_DATA_DIR/server.jar"
    chmod 644 "$MC_DATA_DIR/server.jar"
    rm -rf "$DOWNLOAD_DIR"
    echo "  ✅ Downloaded Minecraft ${MC_VERSION}"
  else
    echo "  ❌ Failed to download server.jar"
    rm -rf "$DOWNLOAD_DIR"
    exit 1
  fi
fi

# ========================================
# CONFIGURAZIONE
# ========================================
echo "📝 Configuring server..."
echo "eula=true" > eula.txt

# Usa variabili ambiente (da workflow inputs) o defaults
WORLDGEN_TYPE="${WORLDGEN_TYPE:-normal}"
WORLDGEN_SEED="${WORLDGEN_SEED:-}"
WORLDGEN_STRUCTURES="${WORLDGEN_STRUCTURES:-true}"
WORLDGEN_BONUS_CHEST="${WORLDGEN_BONUS_CHEST:-false}"
MAX_PLAYERS="${MAX_PLAYERS:-20}"
DIFFICULTY="${DIFFICULTY:-normal}"
GAMEMODE="${GAMEMODE:-survival}"
PVP="${PVP:-true}"
VIEW_DISTANCE="${VIEW_DISTANCE:-10}"
SIMULATION_DISTANCE="${SIMULATION_DISTANCE:-10}"

echo "  Configuration:"
echo "     Version: $MC_VERSION"
echo "     Type: $WORLDGEN_TYPE"
echo "     Seed: ${WORLDGEN_SEED:-random}"
echo "     Structures: $WORLDGEN_STRUCTURES"
echo "     Max Players: $MAX_PLAYERS"
echo "     Difficulty: $DIFFICULTY"
echo "     Gamemode: $GAMEMODE"

# Genera server.properties
cat > server.properties <<EOF
server-port=${MC_PORT}
max-players=${MAX_PLAYERS}
difficulty=${DIFFICULTY}
gamemode=${GAMEMODE}
pvp=${PVP}
enable-command-block=true
spawn-protection=16
max-world-size=29999984
view-distance=${VIEW_DISTANCE}
simulation-distance=${SIMULATION_DISTANCE}
level-type=${WORLDGEN_TYPE}
level-seed=${WORLDGEN_SEED}
generate-structures=${WORLDGEN_STRUCTURES}
bonus-chest=${WORLDGEN_BONUS_CHEST}
EOF

# ========================================
# RESTORE WORLD
# ========================================
if [ -d world ]; then
  echo "📦 Found existing world directory..."
  echo "✅ World will be used!"
else
  echo "🆕 No saved world found, creating new world"
fi

# ========================================
# START SERVER
# ========================================
echo "🎮 Starting Minecraft server..."
java -Xmx${JAVA_HEAP} -Xms${JAVA_HEAP} -jar server.jar nogui &
MC_PID=$!
echo "MC_PID=$MC_PID" >> $GITHUB_ENV

# Save PID to file for backup script
echo "$MC_PID" > "$MC_DATA_DIR/minecraft.pid"

echo "⏳ Waiting for server to start..."
sleep 60

# Verifica che il processo sia ancora attivo
if ps -p $MC_PID > /dev/null; then
  echo "✅ Minecraft server is running!"
else
  echo "❌ Minecraft server failed to start"
  exit 1
fi

# ========================================
# CONNECTION INFO
# ========================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎮 Minecraft Server Connection Information"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📍 Server Address:"
echo "   ${GATEWAY_IP}:${MC_PORT}"
echo ""
echo "Service ID: ${SERVICE_ID}"
echo "Java Heap: ${JAVA_HEAP}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "✅ Minecraft server deployment completed!"
echo "ℹ️  Server process PID: $MC_PID"
echo ""
echo "💡 World data will be automatically compressed and backed up by volume persistence"

