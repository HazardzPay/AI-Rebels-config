# LEGACY — no workflow builds this. Superseded by Dockerfile.stablev2 / Dockerfile.stablev3.
FROM runpod/comfyui:latest

USER root

RUN apt-get update && apt-get install -y curl bash && rm -rf /var/lib/apt/lists/*

COPY docker/boot.sh /opt/boot.sh
RUN chmod +x /opt/boot.sh

ENTRYPOINT ["/opt/boot.sh"]
