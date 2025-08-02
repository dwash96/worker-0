FROM dustinwashington/aider:latest

USER root

RUN <<BASE_EOF
set -e

# Install base packages
apt-get update
apt-get install -y curl wget ca-certificates direnv fzf
rm -rf /var/lib/apt/lists/*

BASE_EOF

RUN <<CODER_EOF
set -e

# Install VS Code Variant(code-server)
CODER_VERSION="4.100.2"
update-ca-certificates
mkdir -p ~/.local/lib ~/.local/bin

curl -fL https://github.com/coder/code-server/releases/download/v$CODER_VERSION/code-server-$CODER_VERSION-linux-amd64.tar.gz \
 | tar -C ~/.local/lib -xz

mv ~/.local/lib/code-server-$CODER_VERSION-linux-amd64 ~/.local/lib/code-server-$CODER_VERSION
ln -s ~/.local/lib/code-server-$CODER_VERSION/bin/code-server ~/.local/bin/code-server
PATH="~/.local/bin:$PATH"
CODER_EOF

RUN <<OTHER_PACKAGES_EOF
set -e

# install yq for yaml parsing
YQ_VERSION="v4.43.1"
YQ_BINARY="yq_linux_amd64"
wget https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}.tar.gz -O - \
 | tar xz && mv ${YQ_BINARY} /usr/local/bin/yq
OTHER_PACKAGES_EOF

RUN <<CONFIG_EOF
set -e

# Create app directory (we'll create project directories dynamically)
mkdir -p /app/.w0
chown -R appuser /app

# Set up direnv for bash
echo 'eval "$(direnv hook bash)"' >> ~/.bashrc

python -m pip install pip-system-certs flask
touch /coder-config.yaml
chown appuser /coder-config.yaml

tee /coder-config.yaml <<'EOF'
bind-addr: 0.0.0.0:4242
auth: password
cert: false
EOF

tee /etc/pip.conf <<'EOF'
[global]
trusted-host = pypi.python.org
               pypi.org
               files.pythonhosted.org
EOF

CONFIG_EOF

ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
ENV PROJECTS_BASE_DIR=/app

COPY ./base/w0.sh ./base/w0.setup.sh ./w0.config.yaml ./w0.vscode.settings.json /app/.w0/

RUN <<SETUP_EOF
set -e

chmod +x /app/.w0/w0.sh
chmod +x /app/.w0/w0.setup.sh

chown appuser /app/.w0/w0.sh
chown appuser /app/.w0/w0.setup.sh
chown appuser /app/.w0/w0.config.yaml

/app/.w0/w0.setup.sh

PROJECTS_BASE_DIR="/app"
for project in $(yq eval '.projects | keys | .[]' /app/.w0/w0.config.yaml 2>/dev/null); do
    project_path="${PROJECTS_BASE_DIR}/${project}"
    mkdir -p "${project_path}"
    chown -R appuser "${project_path}"
    chmod +rwx "${project_path}"
done

SETUP_EOF

WORKDIR /app
USER appuser

# Pre-install VS Code extensions from config file
# Global extensions
RUN <<'EXTENSION_EOF'
# Global extensions from base config
GLOBAL_EXTENSIONS=$(yq eval '.base.extensions[]' /app/.w0/w0.config.yaml 2>/dev/null || echo "")

# Project-specific extensions (all of them to cache them)
PROJECT_EXTENSIONS=""
for project in $(yq eval '.projects | keys | .[]' /app/.w0/w0.config.yaml 2>/dev/null); do
    PROJECT_EXTENSIONS="$PROJECT_EXTENSIONS $(yq eval ".projects.${project}.config.extensions[]" /app/.w0/w0.config.yaml 2>/dev/null || echo "")"
done

# Combine and deduplicate extensions
ALL_EXTENSIONS=$(echo "$GLOBAL_EXTENSIONS $PROJECT_EXTENSIONS" | tr ' ' '\n' | sort -u)

# Install extensions
for ext in $ALL_EXTENSIONS; do
    if [ -n "$ext" ]; then
        echo "Installing VS Code extension: $ext"
        ~/.local/bin/code-server --install-extension "$ext" || echo "Failed to install $ext"
    fi
done

cp /app/.w0/w0.vscode.settings.json ~/.local/share/code-server/User/settings.json

EXTENSION_EOF

ENTRYPOINT ["/app/.w0/w0.sh"]
