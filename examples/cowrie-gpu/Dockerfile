FROM cowrie/cowrie:latest

USER root

# Install fake GPU shim binaries (shell scripts that emit static output)
COPY txtcmds/ /cowrie/share/cowrie/txtcmds/

# Override real /proc and /sys entries via bind-mount prep copies
COPY fakefs/ /fakefs/

# Ensure correct permissions
RUN chmod -R 644 /fakefs/ && \
    find /cowrie/share/cowrie/txtcmds/ -type f -exec chmod 755 {} \;

USER cowrie
