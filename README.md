# Schwarzschild Black Hole Simulator

An interactive real-time black hole ray tracer using CUDA and OpenGL, featuring gravitational lensing effects based on the Schwarzschild metric.

![Black Hole Simulation](screenshot.png)

## Features

- **GPU-accelerated ray tracing** with CUDA for real-time rendering
- **Gravitational lensing** - Einstein rings and light bending
- **Interactive controls** - Auto-rotation, manual camera control, zoom
-**Custom backgrounds** - Use any high-resolution space image
- **High performance** - Runs at 60+ FPS on modern GPUs

## Requirements

- NVIDIA GPU with CUDA support (tested on RTX 2050)
- Ubuntu Linux or WSL2
- CUDA Toolkit
- OpenGL libraries (GLFW, GLEW)

## Installation
```bash
# Install dependencies
sudo apt update
sudo apt install build-essential nvidia-cuda-toolkit
sudo apt install libglfw3-dev libglew-dev libglu1-mesa-dev

# Clone repository
git clone https://github.com/karmakar-rahul/schwarzschild-blackhole-simulator.git
cd schwarzschild-blackhole-simulator

# Compile
nvcc -o blackhole_interactive blackhole_interactive.cu \
  -lglfw -lGL -lGLEW -lGLU -O3

# (Optional) Add a custom background image
convert your_space_image.jpg -resize 4096x4096! galaxy_background.ppm

# Run
./blackhole_interactive
```

## Controls

- **Auto-rotation** - Camera orbits automatically by default
- **Left Click + Drag** - Manual camera control (pauses auto-rotation)
- **Mouse Wheel** - Zoom in/out
- **SPACE** - Toggle auto-rotation on/off
- **R** - Reset camera position
- **ESC** - Exit

## Physics

This simulator implements:
- **Schwarzschild metric** for non-rotating black holes
- **Geodesic ray tracing** through curved spacetime
- **Event horizon** rendering at the Schwarzschild radius
- **Gravitational light bending** creating Einstein rings

## Performance

- Resolution: 1600x900
- Texture: 4K (4096x4096)
- Target FPS: 60+
- Ray steps: 2000 per pixel
# Schwarzschild Black Hole Simulator

An interactive real-time black hole ray tracer using CUDA and OpenGL, featuring gravitational lensing effects based on the Schwarzschild metric.

![Black Hole Simulation](screenshot.png)

## Features

- **GPU-accelerated ray tracing** with CUDA for real-time rendering
- **Gravitational lensing** - Einstein rings and light bending
- **Interactive controls** - Auto-rotation, manual camera control, zoom
-**Custom backgrounds** - Use any high-resolution space image
- **High performance** - Runs at 60+ FPS on modern GPUs

## Requirements

- NVIDIA GPU with CUDA support (tested on RTX 2050)
- Ubuntu Linux or WSL2
- CUDA Toolkit
- OpenGL libraries (GLFW, GLEW)

## Installation
```bash
# Install dependencies
sudo apt update
sudo apt install build-essential nvidia-cuda-toolkit
sudo apt install libglfw3-dev libglew-dev libglu1-mesa-dev

# Clone repository
git clone https://github.com/karmakar-rahul/schwarzschild-blackhole-simulator.git
cd schwarzschild-blackhole-simulator

# Compile
nvcc -o blackhole_interactive blackhole_interactive.cu \
  -lglfw -lGL -lGLEW -lGLU -O3

# (Optional) Add a custom background image
convert your_space_image.jpg -resize 4096x4096! galaxy_background.ppm

# Run
./blackhole_interactive
```

## Controls

- **Auto-rotation** - Camera orbits automatically by default
- **Left Click + Drag** - Manual camera control (pauses auto-rotation)
- **Mouse Wheel** - Zoom in/out
- **SPACE** - Toggle auto-rotation on/off
- **R** - Reset camera position
- **ESC** - Exit

## Physics

This simulator implements:
- **Schwarzschild metric** for non-rotating black holes
- **Geodesic ray tracing** through curved spacetime
- **Event horizon** rendering at the Schwarzschild radius
- **Gravitational light bending** creating Einstein rings

## Performance

- Resolution: 1600x900
- Texture: 4K (4096x4096)
- Target FPS: 60+
- Ray steps: 2000 per pixel

## Screenshots

Add your screenshots here!

## Author

Rahul Karmakar
