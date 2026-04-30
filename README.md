# VK Zig Engine

A Vulkan engine built with Zig, using the [vulkan-zig](https://github.com/Snektron/vulkan-zig) bindings.

## Requirements

- Zig 0.16.0 or later
- Vulkan SDK (for development)

## Dependencies

- [vulkan-zig](https://github.com/Snektron/vulkan-zig) - Zig bindings for Vulkan

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
│   └── main.zig        # Executable entry point
├── registry/
│   └── vk.xml          # Vulkan registry (used by vulkan-zig)
├── build.zig           # Build configuration
└── build.zig.zon       # Dependency manifest
```

## Usage

Import the vulkan module in your code:

```zig
const vulkan = @import("vulkan");
```
