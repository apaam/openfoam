#!/usr/bin/env bash
set -euo pipefail

if [ -n "${APT_MIRROR:-}" ]; then
  sed -i "s|http://archive.ubuntu.com/ubuntu/|${APT_MIRROR}|g; \
          s|http://security.ubuntu.com/ubuntu/|${APT_MIRROR}|g" \
    /etc/apt/sources.list.d/ubuntu.sources
fi

cat > /etc/apt/apt.conf.d/80-docker-retries <<'EOF'
Acquire::Retries "5";
Acquire::http::Timeout "120";
EOF

for attempt in 1 2 3 4 5; do
  if apt-get update; then
    exit 0
  fi
  echo "apt-get update attempt ${attempt} failed, retrying..." >&2
  sleep $((attempt * 5))
done

exit 1
