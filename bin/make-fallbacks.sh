#!/usr/bin/env bash
# Regenerate the Icecast fallback streams so that they match the live streams
# in format (sample rate, channels, codec).
#
# The fallbacks are played while Mopidy switches track, so a listener must not
# notice a format change - otherwise players have to re-initialise their
# decoder and the stream appears to break.
#
# Usage:
#   bin/make-fallbacks.sh            # 48 kHz MP3 / 96 kHz FLAC (default)
#   bin/make-fallbacks.sh 44100 88200
set -euo pipefail

STACK=/home/opencode/mopidy-stack
MP3_RATE=${1:-48000}
OGG_RATE=${2:-96000}

gst-launch-1.0 -q audiotestsrc num-buffers=430 wave=silence \
    ! audioconvert ! "audio/x-raw,rate=$MP3_RATE,channels=2,format=S16LE" \
    ! lamemp3enc target=bitrate cbr=true bitrate=128 \
    ! filesink location="$STACK/web/silence.mp3"

gst-launch-1.0 -q audiotestsrc num-buffers=430 wave=silence \
    ! audioconvert ! "audio/x-raw,rate=$OGG_RATE,channels=2,format=S32LE" \
    ! flacenc ! oggmux ! filesink location="$STACK/web/silence.ogg"

ln -sf "$STACK/web/silence.mp3" "$STACK/icecast/share/icecast/web/silence.mp3"
ln -sf "$STACK/web/silence.ogg" "$STACK/icecast/share/icecast/web/silence.ogg"

echo "Fallbacks regenerated: silence.mp3 (${MP3_RATE} Hz stereo), silence.ogg (${OGG_RATE} Hz stereo)"
echo
echo "Keep the [audio] output in config/mopidy.conf in sync with these rates."
