# AudioPassThroughUniversal

A command-line utility for macOS that captures audio from an aggregate device input and routes it to one or more output channel pairs using CoreAudio and AudioUnit.

## Features

- Select an **Aggregate Device** (created in Audio MIDI Setup) that combines one or more physical input/output devices.
- Route any combination of source channels to any number of destination channels, including duplication and round-robin mapping.
- Minimal dependencies (only Swift, CoreAudio, AudioUnit).
- Optional debug logging controlled by a `DEBUG` flag in the source.

## Requirements

- macOS 12.0 or later
- Swift 5.x toolchain
- Xcode command line tools (for `swiftc`)

## Building

Compile the program as a universal binary (Intel + ARM) via the provided build script:

```bash
chmod +x build.sh
./build.sh
```

Or build manually with Swift:

```bash
swiftc -o AudioPassThroughUniversal AudioPassThrough.swift
```

## Usage

```bash
./AudioPassThroughUniversal <AggregateDeviceName> <SrcChannels> <DstChannels>
```

- `<AggregateDeviceName>`: Name of the aggregate device (see Help below).
- `<SrcChannels>`: String of source channel numbers (e.g. `12` for channels 1 & 2).
- `<DstChannels>`: String of destination channel numbers (e.g. `3456` for channels 3, 4, 5 & 6).

### Help

```bash
./AudioPassThroughUniversal -h
```

Displays usage and lists available **Aggregate Devices** on the system.

## Examples

- **Basic stereo pass-through** (channels 1→3, 2→4):
  ```bash
  ./AudioPassThroughUniversal "MyAggregate" 12 34
  ```

- **Duplicate stereo to two pairs** (1→3,2→4 and 1→5,2→6):
  ```bash
  ./AudioPassThroughUniversal "MyAggregate" 12 3456
  ```

- **Debug mode** (enable by setting `DEBUG = true` in the source and recompiling):
  ```bash
  DEBUG=true ./AudioPassThroughUniversal "MyAggregate" 12 34
  ```

## Aggregate Device Setup

1. Open **Audio MIDI Setup** (macOS Utilities folder).
2. Click the **+** button under **Audio Devices** and choose **Create Aggregate Device**.
3. Add your input (e.g. `BlackHoleA`) and output (e.g. `External Headphones`) devices.
4. Rename the aggregate device to your desired `<AggregateDeviceName>`.

## License

MIT License. See [LICENSE](LICENSE) for details.