FROM mcr.microsoft.com/devcontainers/python:2-3.14-bookworm

# Remove the stale Yarn APT repo so feature installs don't fail on expired keys
RUN rm -f /etc/apt/sources.list.d/yarn.list \
    && rm -rf /var/lib/apt/lists/*
