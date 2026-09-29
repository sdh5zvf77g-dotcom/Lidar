# LiDAR Ground Mapper

Native iPhone/iPad LiDAR scanner that reconstructs the surrounding 3D mesh and provides a **Ground Only** view designed to suppress trees, bushes and other vegetation.

## What it does
- Uses ARKit LiDAR scene reconstruction.
- Builds a live 3D mesh while you walk around.
- Raw Scan / Ground Only display switch.
- Ground extraction uses local lowest-surface sampling plus upward-facing surface filtering.
- Adjustable ground tolerance (5–40 cm).
- Reset scan.
- Export the current ground mesh as OBJ through the iOS share sheet.
- Works without an internet connection after installation.

## Important limitation
ARKit's standard mesh classification does not directly classify vegetation. This app therefore uses geometry rather than claiming that ARKit can identify every plant. Dense vegetation, tall grass, very steep terrain, water, or occluded ground can reduce accuracy.

## Building
Open `LiDARGroundMapper.xcodeproj` in Xcode on a Mac, select a LiDAR-equipped iPhone/iPad, set your development team/signing, and run.

The app requires camera permission. LiDAR scene reconstruction is checked at runtime, so unsupported devices receive a clear message.

## Suggested GitHub repository
Upload this folder to a GitHub repository named `LiDAR-Ground-Mapper`.
