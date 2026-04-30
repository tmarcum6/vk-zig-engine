# VK Zig Engine

A Vulkan engine built with Zig, using the [vulkan-zig](https://github.com/Snektron/vulkan-zig) bindings and GLFW for windowing.

## Requirements

- Zig 0.16.0 or later
- [GLFW](https://www.glfw.org/) (included via Zig package)
- Vulkan SDK or MoltenVK (for macOS)

## macOS Setup

Install MoltenVK (Vulkan implementation over Metal):
```bash
brew install molten-vk
```

Set the Vulkan ICD path:
```bash
export VK_ICD_FILENAMES=/usr/local/share/vulkan/icd.d/MoltenVK_icd.json
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
zig build run
```

## Testing

```bash
zig build test
```

## Project Structure

```
├── src/
│   ├── root.zig        # Library module root
│   ├── main.zig        # Executable entry point
│   └── c/
│       └── glfw.h      # C header for GLFW translation
├── registry/
│   └── vk.xml          # Vulkan registry (used by vulkan-zig)
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
- Vulkan support pending MoltenVK installation (macOS)
- Next: Create Vulkan instance and surface with GLFW
