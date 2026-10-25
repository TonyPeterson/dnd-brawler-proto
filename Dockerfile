FROM ubuntu:22.04

ARG GODOT_VERSION=4.3
ENV GODOT_VERSION=${GODOT_VERSION}

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    unzip \
    ca-certificates \
    libfontconfig1 \
    python3 \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" -O /tmp/godot.zip \
    && unzip /tmp/godot.zip -d /tmp \
    && mv "/tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm -f /tmp/godot.zip

WORKDIR /app
COPY . /app

ENV PORT=10000
EXPOSE 10000

CMD ["sh", "-c", "godot --headless --path /app & python3 -u /app/server_proxy.py"]
