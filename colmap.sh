#!/usr/bin/env -S nix shell --impure nixpkgs#ffmpeg nixpkgs#colmap nixpkgs#opencv4 --command bash

set -euo pipefail

# Define paths
INPUT_VIDEO="data/input.mov"
FRAMES_DIR="data/frames"
COLMAP_DB="data/colmap.db"
SPARSE_DIR="data/sparse"
DENSE_DIR="data/dense"

# Create directories
mkdir -p "$FRAMES_DIR" "$SPARSE_DIR" "$DENSE_DIR"

# Step 1: Extract frames from video
echo "Extracting frames from video..."
ffmpeg -i "$INPUT_VIDEO" -q:v 1 "$FRAMES_DIR/frame_%04d.jpg"

# Step 2: Run COLMAP feature extraction (CPU only)
echo "Running COLMAP feature extraction..."
colmap feature_extractor \
  --database_path "$COLMAP_DB" \
  --image_path "$FRAMES_DIR" \
  --ImageReader.camera_model SIMPLE_RADIAL \
  --SiftExtraction.use_gpu 0

# Step 3: Run COLMAP feature matching (CPU only)
echo "Running COLMAP feature matching..."
colmap exhaustive_matcher \
  --database_path "$COLMAP_DB" \
  --SiftMatching.use_gpu 0

# Step 4: Run COLMAP sparse reconstruction
echo "Running COLMAP sparse reconstruction..."
colmap mapper \
  --database_path "$COLMAP_DB" \
  --image_path "$FRAMES_DIR" \
  --output_path "$SPARSE_DIR"

# Step 5: Run COLMAP dense reconstruction
echo "Running COLMAP image undistorter..."
colmap image_undistorter \
  --image_path "$FRAMES_DIR" \
  --input_path "$SPARSE_DIR/0" \
  --output_path "$DENSE_DIR"

echo "Running COLMAP patch matching (CPU only)..."
colmap patch_match_stereo \
  --workspace_path "$DENSE_DIR" \
  --PatchMatchStereo.gpu_index -1

echo "Running COLMAP stereo fusion..."
colmap stereo_fusion \
  --workspace_path "$DENSE_DIR" \
  --output_path "$DENSE_DIR/fused.ply"

# Output camera pose information for dithering
echo "Extracting camera pose information..."
colmap model_converter \
  --input_path "$SPARSE_DIR/0" \
  --output_path "$SPARSE_DIR/txt" \
  --output_type TXT

echo "COLMAP processing complete!"
echo "Camera poses are in: $SPARSE_DIR/txt/images.txt"
echo "Point cloud is in: $DENSE_DIR/fused.ply"

echo "Script completed successfully"
