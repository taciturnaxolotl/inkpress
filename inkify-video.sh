#!/usr/bin/env -S nix shell nixpkgs#parallel nixpkgs#ffmpeg nixpkgs#imagemagick --command bash

# Define temporary directory variables globally so trap can access them
FRAMES_IN=""
FRAMES_OUT=""

# Function to clean up and exit
cleanup_and_exit() {
    echo -e "\nInterrupted. Cleaning up temporary files..."
    # Only remove if directories were actually created
    [ -n "$FRAMES_IN" ] && [ -d "$FRAMES_IN" ] && rm -rf "$FRAMES_IN"
    [ -n "$FRAMES_OUT" ] && [ -d "$FRAMES_OUT" ] && rm -rf "$FRAMES_OUT"
    exit 1
}

# Set up trap for Ctrl+C (SIGINT)
trap cleanup_and_exit INT

# Check if input and output parameters are provided
if [ $# -lt 2 ]; then
    echo "Usage: $0 input_video output_video [num_threads]"
    exit 1
fi

INPUT_VIDEO=$1
OUTPUT_VIDEO=$2
# Default to number of CPU cores if threads not specified
NUM_THREADS=${3:-$(nproc)}

# Determine and create temporary directories, preferring RAM disk
TEMP_BASE=""
if [ -d "/dev/shm" ] && [ -w "/dev/shm" ]; then
    TEMP_BASE="/dev/shm"
    echo "Using RAM disk (/dev/shm) for temporary files."
elif [ -d "/tmp" ] && [ -w "/tmp" ] && mount | grep -q 'on /tmp type tmpfs'; then
    TEMP_BASE="/tmp"
    echo "Using RAM disk (/tmp) for temporary files."
else
    TEMP_BASE="."
    echo "RAM disk not available or not writable, using current directory for temporary files."
fi

# Create unique temporary directory names using process ID
# Add a random suffix for extra safety in case PID wraps or script runs concurrently
RAND_SUFFIX=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 8)
FRAMES_IN="${TEMP_BASE}/inkify_frames_in_${$}_${RAND_SUFFIX}"
FRAMES_OUT="${TEMP_BASE}/inkify_frames_out_${$}_${RAND_SUFFIX}"

# Check if magick command exists
if ! command -v magick &>/dev/null; then
    echo "Error: ImageMagick (magick command) not found. Please install it."
    # Attempt cleanup before exiting
    [ -d "$FRAMES_IN" ] && rm -rf "$FRAMES_IN"
    [ -d "$FRAMES_OUT" ] && rm -rf "$FRAMES_OUT"
    exit 1
fi

# Check if eink-2color.png exists
if [ ! -f "eink-2color.png" ]; then
    echo "Error: Colormap file 'eink-2color.png' not found in the current directory."
        # Attempt cleanup before exiting
    [ -d "$FRAMES_IN" ] && rm -rf "$FRAMES_IN"
    [ -d "$FRAMES_OUT" ] && rm -rf "$FRAMES_OUT"
    exit 1
fi

# Create temporary directories only after checks pass
mkdir -p "$FRAMES_IN"
if [ $? -ne 0 ]; then echo "Error: Could not create temporary directory $FRAMES_IN"; exit 1; fi
mkdir -p "$FRAMES_OUT"
if [ $? -ne 0 ]; then echo "Error: Could not create temporary directory $FRAMES_OUT"; rm -rf "$FRAMES_IN"; exit 1; fi


# Extract frames from video and detect framerate
FRAMERATE=$(ffprobe -v error -select_streams v -of default=noprint_wrappers=1:nokey=1 -show_entries stream=r_frame_rate "$INPUT_VIDEO" 2>/dev/null | bc -l | awk '{printf "%.2f", $0}')
if [ -z "$FRAMERATE" ] || [ "$FRAMERATE" = "0.00" ]; then
    echo "Error: Could not detect framerate for $INPUT_VIDEO."
    cleanup_and_exit # Use cleanup function
fi
echo "Detected framerate: $FRAMERATE fps"

# Extract frames from video (use -threads for faster extraction)
echo "Extracting frames to $FRAMES_IN..."
if ! ffmpeg -threads "$NUM_THREADS" -i "$INPUT_VIDEO" "$FRAMES_IN/frame_%04d.png" >/dev/null 2>&1; then
    echo "Error: ffmpeg failed to extract frames from $INPUT_VIDEO."
    cleanup_and_exit # Use cleanup function
fi

# Check if frames were extracted
if ! ls "$FRAMES_IN"/frame_*.png > /dev/null 2>&1; then
    echo "Error: No frames were extracted to $FRAMES_IN. Check input video and permissions."
    cleanup_and_exit
fi


# Process frames in parallel using GNU Parallel
if command -v parallel &>/dev/null; then
    echo "Processing frames in parallel with $NUM_THREADS threads..."
    # Need to export FRAMES_OUT for parallel to see it in subshells
    export FRAMES_OUT
    # Use parallel's built-in path manipulation {/} for basename
    if ! find "$FRAMES_IN" -name "frame_*.png" | parallel --progress -j "$NUM_THREADS" \
        "magick {} -dither FloydSteinberg -define dither:diffusion-amount=100% -remap eink-2color.png \"$FRAMES_OUT/{/}\""; then
        echo "Error: Parallel processing with magick failed."
        cleanup_and_exit
    fi
else
    echo "GNU Parallel not found. Processing frames sequentially..."
    # Process each frame with the dithering effect
    processed_count=0
    for frame in "$FRAMES_IN"/frame_*.png; do
        # Check if the file exists before processing
        if [ -f "$frame" ]; then
            # Construct output path correctly using basename
            output_frame="$FRAMES_OUT/$(basename "$frame")"
            if ! magick "$frame" -dither FloydSteinberg -define dither:diffusion-amount=100% -remap eink-2color.png "$output_frame"; then
                 echo "Error: magick failed to process $frame."
                 # Decide if you want to stop on first error or continue
                 cleanup_and_exit # Stop on first error
                 # continue # Or uncomment to continue processing other frames
            fi
            # echo "Processed: $frame" # Can be too verbose
            processed_count=$((processed_count + 1))
        fi
    done
    echo "Processed $processed_count frames sequentially."
    if [ $processed_count -eq 0 ]; then
         echo "Error: No frames found to process sequentially in $FRAMES_IN"
         cleanup_and_exit
    fi
fi

# Check if output frames exist before attempting recombination
if ! ls "$FRAMES_OUT"/frame_*.png > /dev/null 2>&1; then
    echo "Error: No processed frames found in $FRAMES_OUT. Image processing likely failed."
    cleanup_and_exit
fi


# Recombine frames into video with detected framerate (use -threads for faster encoding)
echo "Recombining frames from $FRAMES_OUT..."
# Allow ffmpeg to prompt for overwrite by removing output redirection
if ! ffmpeg -framerate "$FRAMERATE" -threads "$NUM_THREADS" -i "$FRAMES_OUT/frame_%04d.png" -c:v libx264 -preset faster -pix_fmt yuv420p "$OUTPUT_VIDEO"; then
    echo "Error: ffmpeg failed to recombine frames into $OUTPUT_VIDEO (or user cancelled overwrite)."
    cleanup_and_exit # Use cleanup function
fi

# Use the cleanup function for consistency
cleanup_and_exit() {
    echo -e "\nCleaning up temporary files..."
    # Only remove if directories were actually created
    [ -n "$FRAMES_IN" ] && [ -d "$FRAMES_IN" ] && rm -rf "$FRAMES_IN"
    [ -n "$FRAMES_OUT" ] && [ -d "$FRAMES_OUT" ] && rm -rf "$FRAMES_OUT"
}
# Call cleanup explicitly at the end (trap handles interruptions)
cleanup_and_exit
# Reset exit code to 0 for successful completion
exit 0
