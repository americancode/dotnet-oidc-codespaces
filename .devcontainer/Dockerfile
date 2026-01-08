FROM mcr.microsoft.com/devcontainers/dotnet:8.0

ARG DEBIAN_FRONTEND=noninteractive

# Install kind, kubectl, and helm
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl \
  && curl -Lo /usr/local/bin/kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64 \
  && chmod +x /usr/local/bin/kind \
  && curl -Lo /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
  && chmod +x /usr/local/bin/kubectl \
  && curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*
