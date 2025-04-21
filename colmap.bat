@echo off
setlocal

REM --- Windows Batch Version of inky/colmap.sh ---
REM --- Modified to use CUDA for GPU acceleration ---

REM Prerequisites:
REM 1. ffmpeg.exe and colmap.exe must be in the system PATH or the same directory as this script.
REM 2. The COLMAP build MUST support CUDA.
REM 3. Appropriate NVIDIA drivers and CUDA toolkit (compatible with your COLMAP build) must be installed.

REM Define paths (using backslashes for Windows compatibility)
set INPUT_VIDEO=data\input.mov
set FRAMES_DIR=data\frames
set COLMAP_DB=data\colmap.db
set SPARSE_DIR=data\sparse
set DENSE_DIR=data\dense

REM Check if input video exists
if not exist "%INPUT_VIDEO%" (
    echo Error: Input video not found at %INPUT_VIDEO%
    exit /b 1
)

REM Create directories
echo Creating directories...
if not exist "data" mkdir "data"
if not exist "%FRAMES_DIR%" mkdir "%FRAMES_DIR%"
if errorlevel 1 ( echo Failed to create %FRAMES_DIR%. & exit /b 1 )
if not exist "%SPARSE_DIR%" mkdir "%SPARSE_DIR%"
if errorlevel 1 ( echo Failed to create %SPARSE_DIR%. & exit /b 1 )
if not exist "%DENSE_DIR%" mkdir "%DENSE_DIR%"
if errorlevel 1 ( echo Failed to create %DENSE_DIR%. & exit /b 1 )

REM Step 1: Extract frames from video
echo Extracting frames from video...
ffmpeg -i "%INPUT_VIDEO%" -q:v 1 "%FRAMES_DIR%\frame_%%04d.jpg"
if errorlevel 1 (
    echo Error: ffmpeg frame extraction failed. Check ffmpeg output/log.
    exit /b 1
)

REM Step 2: Run COLMAP feature extraction (Using CUDA GPU)
echo Running COLMAP feature extraction (CUDA)...
colmap feature_extractor ^
  --database_path "%COLMAP_DB%" ^
  --image_path "%FRAMES_DIR%" ^
  --ImageReader.camera_model SIMPLE_RADIAL ^
  --SiftExtraction.use_gpu 1
if errorlevel 1 (
    echo Error: COLMAP feature_extractor failed. Check COLMAP output/log. Ensure CUDA is working.
    exit /b 1
)

REM Step 3: Run COLMAP feature matching (Using CUDA GPU)
echo Running COLMAP feature matching (CUDA)...
colmap exhaustive_matcher ^
  --database_path "%COLMAP_DB%" ^
  --SiftMatching.use_gpu 1
if errorlevel 1 (
    echo Error: COLMAP exhaustive_matcher failed. Check COLMAP output/log. Ensure CUDA is working.
    exit /b 1
)

REM Step 4: Run COLMAP sparse reconstruction
REM Note: The 'mapper' step primarily uses CPU.
echo Running COLMAP sparse reconstruction...
colmap mapper ^
  --database_path "%COLMAP_DB%" ^
  --image_path "%FRAMES_DIR%" ^
  --output_path "%SPARSE_DIR%"
if errorlevel 1 (
    echo Warning: COLMAP mapper returned an error code (%ERRORLEVEL%), but proceeding. Check COLMAP output/log.
    REM Mapper might "fail" (e.g., if few matches) but sometimes produces usable results.
    REM More robust checking might be needed depending on COLMAP's specific exit codes.
)

REM Check if the expected output directory from mapper exists
REM COLMAP often creates numbered subdirectories (0, 1, ...) for different models.
REM We assume the first model (0) is the one we want.
if not exist "%SPARSE_DIR%\0" (
    echo Error: Sparse reconstruction output directory (%SPARSE_DIR%\0) not found.
    echo Mapper likely failed to produce a valid reconstruction. Check COLMAP output/log.
    exit /b 1
)

REM Step 5: Run COLMAP dense reconstruction
echo Running COLMAP image undistorter...
colmap image_undistorter ^
  --image_path "%FRAMES_DIR%" ^
  --input_path "%SPARSE_DIR%\0" ^
  --output_path "%DENSE_DIR%"
if errorlevel 1 (
    echo Error: COLMAP image_undistorter failed. Check COLMAP output/log.
    exit /b 1
)

echo Running COLMAP patch matching (Using CUDA GPU)...
REM Use --PatchMatchStereo.gpu_index 0 to select the first CUDA device. Change if needed.
colmap patch_match_stereo ^
  --workspace_path "%DENSE_DIR%" ^
  --PatchMatchStereo.gpu_index 0
if errorlevel 1 (
    echo Error: COLMAP patch_match_stereo failed. Check COLMAP output/log. Ensure CUDA is working.
    exit /b 1
)

echo Running COLMAP stereo fusion...
REM Note: Stereo fusion is primarily CPU-bound.
colmap stereo_fusion ^
  --workspace_path "%DENSE_DIR%" ^
  --output_path "%DENSE_DIR%\fused.ply"
if errorlevel 1 (
    echo Error: COLMAP stereo_fusion failed. Check COLMAP output/log.
    exit /b 1
)

REM Output camera pose information
echo Extracting camera pose information...
colmap model_converter ^
  --input_path "%SPARSE_DIR%\0" ^
  --output_path "%SPARSE_DIR%\txt" ^
  --output_type TXT
if errorlevel 1 (
    echo Error: COLMAP model_converter failed. Check COLMAP output/log.
    exit /b 1
)

echo COLMAP processing complete!
echo Camera poses are in: %SPARSE_DIR%\txt\images.txt
echo Dense point cloud is in: %DENSE_DIR%\fused.ply

echo Script completed successfully
endlocal
exit /b 0
