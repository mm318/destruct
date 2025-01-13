# Destruct

Standalone destruct minigame from Tyrian 2000 (https://tyrian.fandom.com/wiki/Destruct).

![Destruct game screenshot](doc/screenshot.png "Destruct game screenshot")


## Usage

### Installation
```bash
git clone https://github.com/mm318/destruct.git
```

### Build
All commands should be run from the newly downloaded `destruct` directory.

#### Targeting Native Desktop

To build:
```bash
zig build                           # for debug build
zig build -Doptimize=ReleaseSafe    # for release build
```

For convenience, to run:
```bash
zig build run
```

Tested on Ubuntu 20.04 using zig 0.14.0-dev.1911+3bf89f55c (2024.10.0-mach).

#### Targeting Web Browser (experimental)

To build:
```bash
zig build -Doptimize=Debug -Dtarget=wasm32-emscripten       # for debug build
zig build -Doptimize=ReleaseFast -Dtarget=wasm32-emscripten # for release build (recommended)
```

For convenience, to run:
```bash
zig build -Doptimize=ReleaseFast -Dtarget=wasm32-emscripten run
```

Thanks to [sdl-zig-demo-emscripten](https://github.com/silbinarywolf/sdl-zig-demo-emscripten) for a great starting point!

### Develop

To format the source code:
```bash
zig fmt .
