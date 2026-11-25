#!/usr/bin/env bash
# Launch the primary KOX surfaces together for a quick visual review.
set -euo pipefail

for command in kitty notify-send fuzzel; do
    if ! command -v "$command" >/dev/null 2>&1; then
        printf 'visual-test: required command not found: %s\n' "$command" >&2
        exit 1
    fi
done

kitty --title 'KOX Visual Test' bash -lc \
    'printf "KOX OS visual regression check\\n\\nKitty foreground, background, font and padding preview.\\n"; exec bash -i' &

sleep 0.5
notify-send --app-name='KOX Visual Test' \
    'KOX visual regression check' \
    'Mako notification: shared charcoal surface, JetBrains Mono and accent border.'

# Keep the launcher as the final foreground surface for inspection.
exec fuzzel
