# VK Zig Engine

A Vulkan engine built with Zig, using the [vulkan-zig](https://github.com/Snektron/vulkan-zig) bindings and GLFW for windowing.

## Requirements

- Zig 0.16.0 or later
- [GLFW](https://www.glfw.org/) (included via Zig package)
- [MoltenVK](https://vulkan.lunarg.com/) (Vulkan implementation for macOS)

## macOS Setup

Install MoltenVK (Vulkan implementation over Metal):
```bash
brew install molten-vk
```

Create Vulkan ICD configuration:
```bash
sudo mkdir -p /opt/homebrew/share/vulkan/icd.d
```

Create `/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json`:
```json
{
    "file_format_version": "1.0.0",
    "ICD": {
        "library_path": "/opt/homebrew/opt/molten-vk/lib/libMoltenVK.dylib",
        "api_version": "1.2.0"
    }
}
```

Set environment variable (add to `~/.zshrc` or `~/.bashrc`):
```bash
export VK_ICD_FILENAMES=/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json
```

## Dependencies

- [vulkan-zig](https://github.com/Snektron/vulkan-zig) - Zig bindings for Vulkan
- [glfw.zig](https://github.com/tiawl/glfw.zig) - GLFW library for Zig

## Building

```bash
zig build
```

## Running

```bash
VK_ICD_FILENAMES=/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json zig build run
```

## Testing

```bash
zig build test
```

## Project Structure

```
├── src/
│   ├── main.zig        # Main application entry point
│   └── c/
│       └── glfw.h      # C header for GLFW + Vulkan translation
├── registry/
│   └── vk.xml          # Vulkan registry (used by vulkan-zig)
├── moltenvk_include/    # Symlink to MoltenVK Vulkan headers
├── lib_search/          # Symlink to Homebrew lib directory
├── build.zig           # Build configuration
└── build.zig.zon       # Dependency manifest
```

## Usage

Import the modules in your code:

```zig
const vk = @import("vulkan");
const c = @import("c"); // GLFW functions
```

## Current Status

- GLFW window opens successfully
- Vulkan instance creation: **Working**
- Vulkan surface creation: **Working**
- Next: Set up Vulkan device, swapchain, and rendering pipeline
