#!/bin/bash

# Media preview helper for Neovim with image.nvim
# Converts PDF/ODF to images and generates video thumbnails

set -e

PREVIEW_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/nvim_preview"
mkdir -p "$PREVIEW_DIR"

show_usage() {
  echo "Usage: $0 <file>"
  echo "Supported formats: PDF, ODF (odt, ods, odp), MP4, and image formats"
  exit 1
}

if [ -z "$1" ]; then
  show_usage
fi

FILE="$1"
if [ ! -f "$FILE" ]; then
  echo "Error: File not found: $FILE"
  exit 1
fi

# Get file extension
EXT="${FILE##*.}"
EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')

# Generate cache filename
CACHE_FILE="$PREVIEW_DIR/$(echo "$FILE" | md5sum | cut -d' ' -f1)_preview.png"

case "$EXT_LOWER" in
  pdf)
    # Convert first page of PDF to image
    if ! command -v pdftoppm &> /dev/null; then
      echo "Error: pdftoppm not found. Install poppler-utils: brew install poppler"
      exit 1
    fi
    if [ ! -f "$CACHE_FILE" ] || [ "$FILE" -nt "$CACHE_FILE" ]; then
      echo "Converting PDF to image..."
      pdftoppm -png -singlefile -scale-to-x 1920 -scale-to-y -1 "$FILE" "${CACHE_FILE%.png}"
    fi
    ;;

  odt|ods|odp|odf)
    # Convert ODF to PDF, then to image
    if ! command -v libreoffice &> /dev/null && ! command -v soffice &> /dev/null; then
      echo "Error: LibreOffice not found. Install: brew install --cask libreoffice"
      exit 1
    fi

    PDF_FILE="${CACHE_FILE%.png}.pdf"
    if [ ! -f "$PDF_FILE" ] || [ "$FILE" -nt "$PDF_FILE" ]; then
      echo "Converting ODF to PDF..."
      soffice --headless --convert-to pdf --outdir "$PREVIEW_DIR" "$FILE" > /dev/null 2>&1
      mv "$PREVIEW_DIR/$(basename "${FILE%.*}").pdf" "$PDF_FILE"
    fi

    if [ ! -f "$CACHE_FILE" ] || [ "$PDF_FILE" -nt "$CACHE_FILE" ]; then
      echo "Converting PDF to image..."
      pdftoppm -png -singlefile -scale-to-x 1920 -scale-to-y -1 "$PDF_FILE" "${CACHE_FILE%.png}"
    fi
    ;;

  mp4|mov|avi|mkv|webm)
    # Generate video thumbnail
    if ! command -v ffmpeg &> /dev/null; then
      echo "Error: ffmpeg not found. Install: brew install ffmpeg"
      exit 1
    fi
    if [ ! -f "$CACHE_FILE" ] || [ "$FILE" -nt "$CACHE_FILE" ]; then
      echo "Generating video thumbnail..."
      # Extract frame at 10% duration
      ffmpeg -i "$FILE" -vf "select=gte(n\,10)" -frames:v 1 -q:v 2 "$CACHE_FILE" -y > /dev/null 2>&1
    fi
    ;;

  png|jpg|jpeg|gif|webp|bmp)
    # Already an image
    CACHE_FILE="$FILE"
    ;;

  *)
    echo "Error: Unsupported file format: $EXT_LOWER"
    exit 1
    ;;
esac

# Display the image
if [ -f "$CACHE_FILE" ]; then
  if command -v imgcat &> /dev/null; then
    imgcat "$CACHE_FILE"
  else
    echo "Preview generated: $CACHE_FILE"
    echo "Install imgcat: run ~/.dotfiles/scripts/setup_ghostty_imgcat.sh"
  fi
else
  echo "Error: Failed to generate preview"
  exit 1
fi
