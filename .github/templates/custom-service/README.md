# 📦 Atlas Custom Service Template

Template per creare il tuo servizio personalizzato su Atlas con supporto per la persistenza dei volumi.

## 🚀 Quick Start

### 1. Crea la tua Service Repository

```bash
# Usa questo repository come template
gh repo create my-service --template atlas --public

cd my-service
```

### 2. Configura i Volumi

Copia il template di deploy:

```bash
cp .github/templates/custom-service/deploy.sh.example deploy.sh
chmod +x deploy.sh
```

Modifica `deploy.sh` e configura:

```bash
# Path dove il tuo servizio salva i dati
VOLUME_PATH="/tmp/my-service-data"

# Path nella repo per i backup
REPO_DATA_PATH="data/my-service"
```

### 3. Setup Git LFS (per file grandi)

Scegli il preset adatto al tuo servizio:

```bash
# Per database
source .github/lib/volume-persistence.sh
atlas_setup_gitattributes "database"

# Per file media (immagini, video)
atlas_setup_gitattributes "media"

# Per file generici
atlas_setup_gitattributes "general"
```

Oppure crea un `.gitattributes` custom:

```bash
# .gitattributes
data/**/*.db filter=lfs diff=lfs merge=lfs -text
data/**/*.sqlite filter=lfs diff=lfs merge=lfs -text
```

Inizializza Git LFS:

```bash
git lfs install
git add .gitattributes
git commit -m "Setup Git LFS"
```

### 4. Crea il Workflow

Crea `.github/workflows/deploy.yml`:

```yaml
name: Deploy My Service

on:
  workflow_dispatch:
    inputs:
      service_id:
        description: 'Service ID'
        required: true
        default: 'my-service'
      backend_duration_minutes:
        description: 'Durata backend in minuti'
        required: true
        default: '120'
        type: number
      env_vars_json:
        description: 'Environment variables as JSON'
        required: false
        default: '{}'
        type: string

env:
  SERVICE_ID: ${{ github.event.inputs.service_id }}

jobs:
  deploy-service:
    name: Deploy My Service
    runs-on: ubuntu-latest
    timeout-minutes: 360

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Setup Git LFS
        run: |
          git lfs install
          git lfs pull

      - name: Parse environment variables
        run: |
          echo '${{ github.event.inputs.env_vars_json }}' > /tmp/env_vars.json
          python3 -c "
          import json, os
          with open('/tmp/env_vars.json') as f:
              env_vars = json.load(f)
          for key, value in env_vars.items():
              with open(os.environ['GITHUB_ENV'], 'a') as env_file:
                  env_file.write(f'{key}={value}\n')
          "

      - name: Deploy to Atlas
        uses: ./.github/actions/atlas-deploy
        with:
          service_id: ${{ env.SERVICE_ID }}
          peer_prefix: 'my-service'
          backend_duration_minutes: ${{ github.event.inputs.backend_duration_minutes }}
          app_port: '8080'
          protocol: 'http'
          expose: 'host'
          custom_steps_file: 'deploy.sh'
          enable_volume_persistence: 'true'
          gateway_ssh_key: ${{ secrets.ATLAS_GATEWAY_SSH_KEY }}
          gateway_ip: ${{ secrets.ATLAS_GATEWAY_IP }}
          gateway_user: ${{ secrets.ATLAS_GATEWAY_USER }}
          gateway_fqdn: ${{ secrets.ATLAS_GATEWAY_FQDN }}
          registry_url: ${{ secrets.ATLAS_REGISTRY_URL }}
          registry_token: ${{ secrets.ATLAS_REGISTRY_TOKEN }}
```

### 5. Deploy!

```bash
# Trigger dal web UI
# O via CLI
gh workflow run deploy.yml -f service_id=my-service
```

---

## 📚 Volume Persistence Helper API

### Restore Volume

```bash
atlas_restore_volume "<volume_path>" "<repo_data_path>" "[owner]"
```

**Esempio:**
```bash
atlas_restore_volume "/tmp/postgres-data" "data/postgresql" "999:999"
```

### Backup Volume

```bash
atlas_backup_volume "<volume_path>" "<repo_data_path>" "[container_name]"
```

**Esempio:**
```bash
atlas_backup_volume "/tmp/myapp-data" "data/myapp" "myapp-container"
```

### Commit Volumes

```bash
atlas_commit_volumes "[commit_message]"
```

**Esempio:**
```bash
atlas_commit_volumes "Updated database after migration"
```

### Setup Git Attributes

```bash
atlas_setup_gitattributes "<preset>"
# preset: database | media | general | custom
```

### Volume Stats

```bash
atlas_volume_stats "<volume_path>"
```

---

## 🎯 Esempi Pratici

### Esempio 1: Node.js App con SQLite

```bash
# deploy.sh
source .github/lib/volume-persistence.sh

VOLUME_PATH="/tmp/myapp-data"
REPO_DATA_PATH="data/myapp"

# Restore
atlas_restore_volume "$VOLUME_PATH" "$REPO_DATA_PATH"

# Deploy
docker run -d \
  --name myapp \
  -v "$VOLUME_PATH:/app/data" \
  -p 3000:3000 \
  my-node-app:latest

# Stats
atlas_volume_stats "$VOLUME_PATH"
```

### Esempio 2: Python App con File Upload

```bash
# deploy.sh
source .github/lib/volume-persistence.sh

VOLUME_PATH="/tmp/uploads"
REPO_DATA_PATH="data/uploads"

atlas_restore_volume "$VOLUME_PATH" "$REPO_DATA_PATH" "1000:1000"

docker run -d \
  --name flask-app \
  -v "$VOLUME_PATH:/app/uploads" \
  -p 5000:5000 \
  my-flask-app:latest
```

### Esempio 3: MongoDB

```bash
# deploy.sh
source .github/lib/volume-persistence.sh

VOLUME_PATH="/tmp/mongodb-data"
REPO_DATA_PATH="data/mongodb"

atlas_restore_volume "$VOLUME_PATH" "$REPO_DATA_PATH" "999:999"

docker run -d \
  --name mongodb \
  -v "$VOLUME_PATH:/data/db" \
  -p 27017:27017 \
  mongo:latest

# Health check
sleep 5
docker exec mongodb mongosh --eval "db.adminCommand('ping')"

atlas_volume_stats "$VOLUME_PATH"
```

---

## 📏 Limiti e Best Practices

### Git LFS Limits (GitHub Free)
- **Storage**: 1 GB incluso
- **Bandwidth**: 1 GB/month incluso
- **Costo extra**: $5/month per 50GB storage + 50GB bandwidth

### Best Practices

1. **Usa Git LFS per file > 50MB**
   ```bash
   atlas_setup_gitattributes "database"
   ```

2. **Fai cleanup periodico**
   - Elimina backup vecchi dal repository
   - Usa retention policy (es. mantieni solo ultimi 5 backup)

3. **Comprimi dati quando possibile**
   ```bash
   tar czf - "$VOLUME_PATH" | docker exec -i container tar xzf - -C /data
   ```

4. **Stop container prima del backup** (per database)
   ```bash
   atlas_backup_volume "$VOLUME_PATH" "$REPO_DATA_PATH" "postgres"
   ```

5. **Test il restore!**
   ```bash
   # In locale
   git clone your-service-repo
   cd your-service-repo
   source .github/lib/volume-persistence.sh
   atlas_restore_volume "/tmp/test" "data/myapp"
   ls -lah /tmp/test
   ```

---

## 🆘 Troubleshooting

### Problema: "Permission denied" durante restore

```bash
# Soluzione: specifica owner corretto
atlas_restore_volume "$VOLUME_PATH" "$REPO_DATA_PATH" "1000:1000"
```

### Problema: File troppo grandi per GitHub

```bash
# Soluzione 1: Setup Git LFS
atlas_setup_gitattributes "database"
git lfs install
git lfs migrate import --include="*.db"

# Soluzione 2: Usa compression
tar czf backup.tar.gz "$VOLUME_PATH"
```

### Problema: Backup troppo lento

```bash
# Soluzione: Escludi file temporanei
rsync -av --delete --exclude='*.log' --exclude='tmp/*' \
  "$VOLUME_PATH/" "$REPO_DATA_PATH/"
```

---

## 📞 Support

- **Documentation**: [Atlas Docs](https://github.com/your-org/atlas/docs)
- **Issues**: [GitHub Issues](https://github.com/your-org/atlas/issues)
- **Examples**: [Atlas Examples](https://github.com/your-org/atlas-examples)
