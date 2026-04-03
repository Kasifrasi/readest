# Wir nutzen dein bisheriges Image als Basis
FROM ivangabriele/tauri:debian-bookworm-22

# 1. System-Abhängigkeiten installieren (Git & Curl)
# (Das rm -rf am Ende bereinigt den apt-Cache, um das Image klein zu halten)
RUN apt-get update && \
    apt-get install -y git curl && \
    rm -rf /var/lib/apt/lists/*

# 2. Git-Town installieren
RUN curl -L https://git-town.com/install.sh | sh

# 3. Cocogitto installieren (stellt den 'cog' Befehl bereit)
# Da wir als root agieren, landet das in /root/.cargo/bin/cog
RUN cargo install cocogitto

# Optional: Sicherstellen, dass das Cargo-Bin-Verzeichnis im PATH ist,
# falls das Basis-Image das nicht ohnehin schon tut.
ENV PATH="/root/.cargo/bin:${PATH}"
