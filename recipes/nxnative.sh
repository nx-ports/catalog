#!/bin/bash
# Frontport Recipe: nxnative (seedds/nxnative), Nintendo Switch games whose own arm64 code runs natively,
# with the Switch's system and its NVN graphics stood in for by a host on macOS and Metal.
# Contract: catalog/recipes/README.md. Invoked as `nxnative.sh fetch`, then `nxnative.sh build`.
#
# One Recipe for one Port per game: the Port id names the game (the case below). nxnative has no Mac app, only its
# development host, dmhost, which runs a game in a window from files its NSP script prepares. So build runs that
# script on the Build-Stage NSPs (`--platform mac`), then links dmhost again with a small launcher as its main, which
# sets the host's paths for the sandbox (game files in the Build Assets, saves in the container) and calls dmhost's
# own main, renamed. One executable: AppKit aborts its check-in in a program the app execs, which Frontport signs
# with `inherit`.
#
# Build Assets: everything made from the NSPs, left at $FRONTPORT_OUT/assets for the Catalog's buildAssets.path
# "Contents/Resources/game": romfs/ (the game files), patched/ (the game's code modules, rewritten by nxnative's
# patch_nso.py), shaders/ (the game's shaders translated to Metal libraries), profile/ (the game profile's shader
# tables, which name those libraries) and nxnative.txt (the nxnative commit they were made with; the launcher
# refuses others, since rewritten code only runs in the host it was rewritten for), and aoc/ (each DLC's files, when
# DLC NSPs come as extras). For a game that compiles shaders as it starts (Three Houses), the script also boots the
# game headless in the host it builds, which needs the GPU the build sandbox grants.
#
# Upstream needs Homebrew's dotnet, spirv-cross and zstd and pip's lz4, capstone, fonttools and nsz. This fetches each
# pinned instead (.NET 10 SDK, a standalone Python 3.14, wheels, sources built into the prefix), LibHac, which
# nx_extract restores from NuGet, under a lock file, and hactool, for the check below. Xcode's Metal toolchain must be
# installed (xcodebuild -downloadComponent MetalToolchain): $FRONTPORT_METAL is its bin folder.
#
# The script finds a wrong game file only by its build IDs, after the extraction (half an hour), and packs it all the
# same from a profile it derives. So build first reads each game file's content meta, which hactool decrypts, and stops
# unless it holds the game, its update at the version the game profile packs, or its DLC.
#
# Frontport keeps nsz's NSZ and XCZ files compressed. Build makes each into the NSP or XCI it was made from with nsz's
# own decompressor, the one nsz -D runs (nsz -D itself starts a multiprocessing manager, whose Unix socket the build
# sandbox refuses), and keeps it in Builds/<port>/unpacked for the next build.
set -euo pipefail

step=${1:?usage: nxnative.sh fetch|build}
src=$FRONTPORT_SRC
work=$(dirname "$src")                 # Builds/<port>: writable during build, kept between builds
nx=$src/nxnative
deps=$src/deps
prefix=$work/prefix                    # spirv-cross, zstd and hactool, reused while their pins don't change
export GIT_CEILING_DIRECTORIES=$work

fail() {
    echo "error: $*" >&2
    exit 1
}

# Each Port's game: its base title ID, which names nxnative's game profile, and the app's name.
case "$FRONTPORT_PORT" in
    nxnative-wonder) title=010015100B514000 app_name="Super Mario Bros. Wonder" ;;
    nxnative-totk) title=0100F2C0115B6000 app_name="Tears of the Kingdom" ;;
    nxnative-three-houses) title=010055D009F78000 app_name="Fire Emblem Three Houses" ;;
    nxnative-links-awakening) title=01006BB00C6F0000 app_name="Link's Awakening" ;;
    *) fail "Port $FRONTPORT_PORT names no game this Recipe builds (nxnative-wonder, nxnative-totk, nxnative-three-houses, nxnative-links-awakening)" ;;
esac

# name sha256-or-sha512 url. Archives unpack into deps/<name>; wheels are kept in deps/wheels, and NuGet packages in
# deps/feed, the one package source nx_extract restores from.
downloads="
dotnet ee0d379c144ebddef6efe851e1514883d1b695430d13b3fb13e8153f8476e1e5ac7abc42c08668471aaf4d738ff367cf53009845f94d224ba126febe74d00b75 https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.402/dotnet-sdk-10.0.402-osx-arm64.tar.gz
python 226d696642a8a53d03b4d5b255b1c319b1575a6d44bd723a953c9f507755e36a https://github.com/astral-sh/python-build-standalone/releases/download/20261021/cpython-3.14.9%2B20261021-aarch64-apple-darwin-install_only.tar.gz
spirv-cross 92b0458889ed77eac9892b3be5a41e3cf716849fd90f39632e159e555abf3d03 https://github.com/KhronosGroup/SPIRV-Cross/archive/f11ba9f0b21ba8fc15153d50a2a1ae31ab1cf8f7.tar.gz
zstd eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3 https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz
hactool f7148daad624ba909f5ae253210734b1a0ce19e89a7914b6cf71401f7134ebbc https://github.com/SciresM/hactool/archive/1d64a83450e025622f3468c28fc4164dad2c5ef6.tar.gz
lz4-4.4.5-cp314-cp314-macosx_11_0_arm64.whl c8e71b14938082ebaf78144f3b3917ac715f72d14c076f384a4c062df96f9df6 https://files.pythonhosted.org/packages/b6/cb/bfead8f437741ce51e14b3c7d404e3a1f6b409c440bad9b8f3945d4c40a7/lz4-4.4.5-cp314-cp314-macosx_11_0_arm64.whl
capstone-5.0.9-py3-none-macosx_11_0_arm64.whl fc269c5082e17d7f9f265cd6980e2fdc6ab572df913951d76db0357e06b8001d https://files.pythonhosted.org/packages/42/9a/4eecfbc94961cda70301fd13de69042be1943bee456e37bc1369840601b1/capstone-5.0.9-py3-none-macosx_11_0_arm64.whl
fonttools-4.67.0-py3-none-any.whl 4304f03ed7f4ba000a8dcc941ad854bfa52e2f3b6112b8f099b6f431cf98e701 https://files.pythonhosted.org/packages/3d/61/4161946319472aaa9b897bd18ad5108a5b10f5ebaa503d921a001ac4fff9/fonttools-4.67.0-py3-none-any.whl
nsz-5.0.0-py3-none-any.whl b3698cab8d7720aed056a0290017ff60a989d8343b7bb9c3c161ab137ec03965 https://files.pythonhosted.org/packages/85/7f/e11c738d92ffa58116184b443636b27c4cdefc0a7d73e5eacff1c9e3b6dd/nsz-5.0.0-py3-none-any.whl
pycryptodome-4.2.0-cp39-abi3-macosx_10_9_universal2.whl 3e430168f767ecec60c1f850df4abbd0b9f94786b9cc8041a00e976f6d5190c6 https://files.pythonhosted.org/packages/41/4c/954a9a1451f7bcc89d66db39bf6499ef5701e8ff35b6c898c659a7ec8546/pycryptodome-4.2.0-cp39-abi3-macosx_10_9_universal2.whl
zstandard-0.25.0-cp314-cp314-macosx_11_0_arm64.whl 05df5136bc5a011f33cd25bc9f506e7426c0c9b3f9954f056831ce68f3b6689f https://files.pythonhosted.org/packages/8d/09/d0a2a14fc3439c5f874042dca72a79c70a532090b7ba0003be73fee37ae2/zstandard-0.25.0-cp314-cp314-macosx_11_0_arm64.whl
enlighten-1.14.1-py2.py3-none-any.whl 5fbd0c959ca1644034c41bb0ace5db19c9852cf9d721b6103f5f130663c57be8 https://files.pythonhosted.org/packages/73/1e/244bb2fc5713ad21ae9f9012067f6432c682593816c6a45372c24f5a7d61/enlighten-1.14.1-py2.py3-none-any.whl
blessed-1.52.0-py3-none-any.whl 1936f421f3feb130035a4629e6477d1432e33b2674ab2b9841292c74d479eac2 https://files.pythonhosted.org/packages/29/1f/88e64e3b4a8299fcc47dd0db35276ca21c18fadad4e8eb25afad546404c6/blessed-1.52.0-py3-none-any.whl
jinxed-2.1.0-py2.py3-none-any.whl 43b802d18b70e405d410fb66eb2837d1101e7e5ea922e666507bb43f34d11d09 https://files.pythonhosted.org/packages/f1/1d/0a6be99b69bb448448403a45a241aff0dca751832ae54f027ed940d2eb52/jinxed-2.1.0-py2.py3-none-any.whl
wcwidth-0.9.4-cp310-abi3-macosx_11_0_arm64.whl f279f32c8e206a9092fa350e53ca0c2bd8072e45b1c9fd31bb6d476b59b591c4 https://files.pythonhosted.org/packages/04/e9/dfdca30ca36c472de3e260406dee29fc108499ec590c63b3fe279887ee9d/wcwidth-0.9.4-cp310-abi3-macosx_11_0_arm64.whl
prefixed-0.9.0-py2.py3-none-any.whl 3cdb74bfc4cf0aba28f3574662b13afdcac27c463dcbef320fe5d03f4c5fbca8 https://files.pythonhosted.org/packages/c3/61/d9957a0ed189ac8a89075c59c97588fb1c77e51d8d44a26f5cdf001d260c/prefixed-0.9.0-py2.py3-none-any.whl
libhac.0.19.0.nupkg 856b2ba6135cc651c6d95f217bd3ebbfec34d2dee0c6446b15436381d43ad07b0ca4b47affaf6a1ba7765d7bba7b7972aa20cbdfcb28399eebf0a16800938647 https://api.nuget.org/v3-flatcontainer/libhac/0.19.0/libhac.0.19.0.nupkg
"

# nx_extract's one NuGet package, pinned again by NuGet's own content hash: restore fails in locked mode on any other.
# .NET's TLS can't run in the fetch sandbox, so restore never goes online: curl fetches the package above instead.
nx_extract_lock='{
  "version": 1,
  "dependencies": {
    "net10.0": {
      "LibHac": {
        "type": "Direct",
        "requested": "[0.19.0, )",
        "resolved": "0.19.0",
        "contentHash": "7uMUGFpO2V0XJowS5/NjX6qlAlO94dQhLvxNdF3VhW36BXkoHCJPxTzL9r0U4p8w0jKm+9oAUF6XriWrAbIrsw=="
      }
    }
  }
}'

# .NET, NuGet and MSBuild without first-run work, telemetry, servers or nodes left running, all inside $HOME.
dotnet_environment() {
    export DOTNET_ROOT=$deps/dotnet
    export DOTNET_CLI_HOME=$HOME NUGET_PACKAGES=$src/nuget
    export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1 DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
    export DOTNET_CLI_WORKLOAD_UPDATE_NOTIFY_DISABLE=1 DOTNET_GENERATE_ASPNET_CERTIFICATE=false
    export DOTNET_CLI_USE_MSBUILD_SERVER=0 MSBUILDDISABLENODEREUSE=1 UseSharedCompilation=false
    export RestoreLockedMode=true
    export PATH=$DOTNET_ROOT:$PATH
}

fetch() {
    case "$FRONTPORT_REF" in
        [0-9a-f]*) [ ${#FRONTPORT_REF} -eq 40 ] || fail "pin nxnative by its full commit, not $FRONTPORT_REF" ;;
        *) fail "pin nxnative by its full commit, not $FRONTPORT_REF" ;;
    esac
    echo "==> Fetching nxnative $FRONTPORT_REF"
    git init --quiet "$nx"
    git -C "$nx" fetch --quiet --depth 1 https://github.com/seedds/nxnative.git "$FRONTPORT_REF"
    git -c advice.detachedHead=false -C "$nx" checkout --quiet FETCH_HEAD
    [ "$(git -C "$nx" rev-parse HEAD)" = "$FRONTPORT_REF" ] || fail "the fetched commit isn't $FRONTPORT_REF"

    mkdir -p "$deps/wheels" "$deps/feed"
    local name sha url file algorithm
    while read -r name sha url; do
        [ -n "$name" ] || continue
        echo "==> Downloading $name"
        file=$deps/$name.download
        curl -fsSL --retry 3 -o "$file" "$url"
        algorithm=$((${#sha} * 4))
        echo "$sha  $file" | shasum -a "$algorithm" -c --status - || fail "$name doesn't match its pinned sha$algorithm"
        case "$name" in
            *.whl) mv "$file" "$deps/wheels/$name" ;;
            *.nupkg) mv "$file" "$deps/feed/$name" ;;
            dotnet)
                mkdir -p "$deps/dotnet"
                tar -xzf "$file" -C "$deps/dotnet"
                rm "$file"
                ;;
            *)
                mkdir -p "$deps/$name"
                tar -xzf "$file" -C "$deps/$name" --strip-components=1
                rm "$file"
                ;;
        esac
    done <<<"$downloads"

    echo "==> Installing Python packages"
    "$deps/python/bin/python3" -I -m pip install --quiet --no-index --no-deps --no-compile \
        --disable-pip-version-check "$deps"/wheels/*.whl

    echo "==> Restoring nx_extract's packages"
    printf '%s\n' "$nx_extract_lock" >"$nx/dm/tools/nx_extract/packages.lock.json"
    cat >"$nx/dm/tools/nx_extract/NuGet.Config" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="frontport" value="$deps/feed" />
  </packageSources>
</configuration>
EOF
    dotnet_environment
    dotnet restore "$nx/dm/tools/nx_extract" --locked-mode -nologo -v quiet
}

# spirv-cross, zstd and hactool into the prefix, rebuilt only when their pins change.
build_tools() {
    local stamp=$prefix/stamp want
    want=$(echo "$downloads" | grep -E '^(spirv-cross|zstd|hactool) ' | shasum -a 256 | cut -d' ' -f1)
    if [ -x "$prefix/bin/spirv-cross" ] && [ -x "$prefix/bin/zstd" ] && [ -x "$prefix/bin/hactool" ] &&
        [ "$(cat "$stamp" 2>/dev/null)" = "$want" ]; then
        return
    fi
    rm -rf "$prefix" "$work/build"
    echo "==> Building spirv-cross"
    cmake -S "$deps/spirv-cross" -B "$work/build/spirv-cross" -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_INSTALL_PREFIX="$prefix" -DSPIRV_CROSS_SHARED=OFF \
        -DSPIRV_CROSS_ENABLE_TESTS=OFF -DSPIRV_CROSS_CLI=ON
    cmake --build "$work/build/spirv-cross" -j "$FRONTPORT_JOBS"
    cmake --install "$work/build/spirv-cross" >/dev/null
    echo "==> Building zstd"
    cmake -S "$deps/zstd/build/cmake" -B "$work/build/zstd" -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_INSTALL_PREFIX="$prefix" -DZSTD_BUILD_PROGRAMS=ON \
        -DZSTD_BUILD_SHARED=OFF -DZSTD_BUILD_TESTS=OFF -DZSTD_PROGRAMS_LINK_SHARED=OFF
    cmake --build "$work/build/zstd" -j "$FRONTPORT_JOBS" --target zstd
    cp "$work/build/zstd/programs/zstd" "$prefix/bin/zstd"
    echo "==> Building hactool"
    cp -R "$deps/hactool" "$work/build/hactool"
    cp "$work/build/hactool/config.mk.template" "$work/build/hactool/config.mk"
    make -C "$work/build/hactool" -j "$FRONTPORT_JOBS" CC=clang >/dev/null
    cp "$work/build/hactool/hactool" "$prefix/bin/hactool"
    echo "$want" >"$stamp"
}

# xcrun in the build sandbox can't find Xcode's Metal toolchain, which Xcode mounts inside the home folder, so this
# one runs metal and metallib from $FRONTPORT_METAL, with the compiler's module cache in $TMPDIR instead of the
# per-user cache folder, and passes everything else to the real xcrun. nxnative calls `xcrun -sdk <sdk> metal`.
make_xcrun() {
    local bin=$work/bin
    mkdir -p "$bin"
    cat >"$bin/xcrun" <<'EOF'
#!/bin/bash
all=("$@")
while [ $# -gt 0 ]; do
    case "$1" in
        -sdk | --sdk) shift 2 ;;
        *) break ;;
    esac
done
case "${1:-}" in
    metal)
        shift
        [ -n "${FRONTPORT_METAL:-}" ] || { echo "error: Xcode's Metal toolchain isn't installed: xcodebuild -downloadComponent MetalToolchain" >&2; exit 1; }
        exec "$FRONTPORT_METAL/metal" -fmodules-cache-path="$TMPDIR/metal-modules" "$@"
        ;;
    metallib)
        shift
        [ -n "${FRONTPORT_METAL:-}" ] || { echo "error: Xcode's Metal toolchain isn't installed: xcodebuild -downloadComponent MetalToolchain" >&2; exit 1; }
        exec "$FRONTPORT_METAL/metallib" "$@"
        ;;
esac
exec /usr/bin/xcrun "${all[@]}"
EOF
    chmod +x "$bin/xcrun"
    export PATH=$bin:$PATH
}

# The launcher, the app's main: points the host at the Build Assets, keeps the game's saves and temporary storage
# in the container, then runs dmhost's main, which the host's build renames dmhost_main.
write_launcher() {
    cat >"$1" <<'EOF'
// The Port's main, added by Frontport's nxnative Recipe: sets dmhost's paths, then runs its main.
#include <errno.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static void need(int ok, const char *what) {
    if (!ok) { fprintf(stderr, "nxnative: %s: %s\n", what, strerror(errno)); exit(1); }
}

static char *join(const char *a, const char *b) {
    char *s; need(asprintf(&s, "%s/%s", a, b) > 0, "out of memory"); return s;
}

static int exists(const char *path) { struct stat st; return stat(path, &st) == 0; }

static void folders(char *path) {   // mkdir -p
    for (char *p = path + 1; *p; p++) if (*p == '/') { *p = 0; mkdir(path, 0700); *p = '/'; }
    need(mkdir(path, 0700) == 0 || errno == EEXIST, path);
}

int dmhost_main(int argc, char **argv);

// KEY=VALUE lines in Data's env.txt win over everything, as Documents/env.txt does on an iPhone.
static void env_file(const char *path) {
    FILE *f = fopen(path, "r"); if (!f) return;
    char line[4096];
    while (fgets(line, sizeof line, f)) {
        line[strcspn(line, "\r\n")] = 0;
        char *eq = strchr(line, '=');
        if (line[0] == '#' || !eq || eq == line) continue;
        *eq = 0; setenv(line, eq + 1, 1);
    }
    fclose(f);
}

int main(int argc, char **argv) {
    char exe[PATH_MAX], contents[PATH_MAX]; uint32_t size = sizeof exe;
    need(_NSGetExecutablePath(exe, &size) == 0 && realpath(exe, contents), "can't find the app");
    *strrchr(contents, '/') = 0; *strrchr(contents, '/') = 0;
    char *resources = join(contents, "Resources"), *game = join(resources, "game");
    const char *home = getenv("HOME"); need(home != NULL, "HOME isn't set");
    char *data = join(home, "Library/Application Support/nxnative");
    char *save = join(data, "save"), *temp = join(data, "temp");
    folders(save); folders(temp);

    // Rewritten code runs only in the host it was rewritten for.
    char made[128] = ""; FILE *f = fopen(join(game, "nxnative.txt"), "r");
    if (f) { if (fgets(made, sizeof made, f)) made[strcspn(made, "\r\n")] = 0; fclose(f); }
    if (strcmp(made, NXNATIVE_REF)) {
        fprintf(stderr, "nxnative: the game files were made by nxnative %s, not %s: update the Port to make them again\n",
            *made ? made : "(none)", NXNATIVE_REF);
        return 1;
    }

    env_file(join(data, "env.txt"));
    setenv("DM_ROOT", data, 0);
    setenv("DM_SAVE", save, 0);
    setenv("DM_TEMP", temp, 0);
    setenv("DM_ROMFS", join(game, "romfs"), 0);
    setenv("DM_MSL_DIR", join(game, "shaders"), 0);
    char *shmap = join(game, "profile/shader_map.tsv"), *aoc = join(game, "aoc");
    if (exists(shmap)) setenv("DM_NVN_SHMAP", shmap, 0);
    if (exists(aoc)) setenv("DM_AOC_DIR", aoc, 0);
    setenv("DM_FONT_DIR", join(resources, "font"), 0);
    setenv("DM_LANG", "en-US", 0);
    setenv("DM_WINDOW", "1", 0);
    setenv("DM_AUDIO", "1", 0);
    need(chdir(data) == 0, data);

    char **args = calloc((size_t)argc + 2, sizeof *args); int n = 0;
    args[n++] = argv[0]; args[n++] = join(game, "patched");
    for (int i = 1; i < argc; i++) if (strncmp(argv[i], "-psn_", 5)) args[n++] = argv[i];
    return dmhost_main(n, args);
}
EOF
}

# The app's executable: dmhost as make builds it for the game profile, its main renamed dmhost_main (main.c holds the
# only `main` in the host's sources), linked with the launcher, which is compiled apart so it keeps its own main.
build_executable() {
    local output=$1 line
    write_launcher "$work/launcher.c"
    clang -c -O2 -Wall -arch arm64 -mmacosx-version-min=26.0 -DNXNATIVE_REF="\"$FRONTPORT_REF\"" \
        -o "$work/launcher.o" "$work/launcher.c"
    make -C "$nx/dm/host" -s GAME="$title" "gen/$title/game_profile.h" gen/vpx/libvpx.a
    line=$(make -C "$nx/dm/host" -n -B GAME="$title" dmhost | grep -e ' -o dmhost ') ||
        fail "make gave no compile line for dmhost"
    (cd "$nx/dm/host" && eval "${line/ -o dmhost / -Dmain=dmhost_main \"$work/launcher.o\" -o \"$output\" }")
    # The host's -g leaves debug symbols beside the executable, which the app doesn't need.
    rm -rf "$output.dSYM"
}

# make_icon <image> <icns>: the game's icon (the 256-pixel JPEG nx_extract saves from the control data) as an app
# icon. sips and iconutil need LaunchServices, which the build sandbox doesn't offer, but ImageIO itself works there:
# a small tool draws it as a rounded square on macOS's 1024-pixel icon grid, and the icon holds that PNG as is.
make_icon() {
    cat >"$work/make_icon.c" <<'EOF'
// make_icon <image> <png>: an image as a macOS app icon, a rounded square on the 1024-pixel icon grid.
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>
#include <stdio.h>
#include <string.h>

static CFURLRef url(const char *path) {
    return CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path, (CFIndex)strlen(path), false);
}

int main(int argc, char **argv) {
    if (argc != 3) { fprintf(stderr, "usage: make_icon <image> <png>\n"); return 2; }
    CGImageSourceRef source = CGImageSourceCreateWithURL(url(argv[1]), NULL);
    CGImageRef image = source ? CGImageSourceCreateImageAtIndex(source, 0, NULL) : NULL;
    if (!image) { fprintf(stderr, "make_icon: can't read %s\n", argv[1]); return 1; }

    // The grid's 824-pixel square with 185.4-pixel corners, centred, over a soft shadow.
    CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(NULL, 1024, 1024, 8, 0, srgb, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGRect square = CGRectMake(100, 100, 824, 824);
    CGPathRef shape = CGPathCreateWithRoundedRect(square, 185.4, 185.4, NULL);
    CGFloat shadow[] = {0, 0, 0, 0.3};
    CGContextSaveGState(context);
    CGContextSetShadowWithColor(context, CGSizeMake(0, -10), 20, CGColorCreate(srgb, shadow));
    CGContextAddPath(context, shape);
    CGContextFillPath(context);
    CGContextRestoreGState(context);
    CGContextAddPath(context, shape);
    CGContextClip(context);
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGContextDrawImage(context, square, image);

    CGImageDestinationRef png = CGImageDestinationCreateWithURL(url(argv[2]), CFSTR("public.png"), 1, NULL);
    if (png) CGImageDestinationAddImage(png, CGBitmapContextCreateImage(context), NULL);
    if (!png || !CGImageDestinationFinalize(png)) { fprintf(stderr, "make_icon: can't write %s\n", argv[2]); return 1; }
    return 0;
}
EOF
    clang -O2 -Wall -arch arm64 -mmacosx-version-min=26.0 -framework CoreFoundation -framework CoreGraphics \
        -framework ImageIO -o "$work/make_icon" "$work/make_icon.c"
    "$work/make_icon" "$1" "$work/icon.png"
    "$deps/python/bin/python3" -I - "$work/icon.png" "$2" <<'EOF'
import struct, sys
png = open(sys.argv[1], "rb").read()
assert png[:8] == b"\x89PNG\r\n\x1a\n" and png[16:24] == struct.pack(">II", 1024, 1024), "unusable icon"
open(sys.argv[2], "wb").write(b"icns" + struct.pack(">I", len(png) + 16) + b"ic10" + struct.pack(">I", len(png) + 8) + png)
EOF
}

# check_games <keys> <version> <display version> <game file>...: stops the build unless each game file is the game (its
# version 0), its update at the version the game profile packs, or its DLC, with the game and the update both there. A
# file's content meta (title ID, version, kind) is in its meta NCA, which an NSZ and an XCZ keep as it is: this copies
# that NCA out, hactool decrypts it, and this reads the content meta it writes. Seconds, not the extraction's half hour.
check_games() {
    "$deps/python/bin/python3" -I - "$prefix/bin/hactool" "$TMPDIR/meta" "$title" "$app_name" "$@" <<'EOF'
import glob, os, re, shutil, struct, subprocess, sys

hactool, tmp, title, name, keys, version, display = sys.argv[1:8]
base, update, version = int(title, 16), int(title, 16) | 0x800, int(version)
KINDS = {0x80: 'base game', 0x81: 'update', 0x82: 'DLC'}


def fail(why):
    sys.exit(f'error: {why}')


def table(f, at, magic):
    """The files of a PFS0 (an NSP or NSZ) or an HFS0 (a partition of an XCI or XCZ) at `at`, as (name, offset, size)."""
    f.seek(at)
    head = f.read(16)
    if len(head) < 16 or head[:4] != magic:
        return None
    count, names = struct.unpack_from('<II', head, 4)
    size = 0x18 if magic == b'PFS0' else 0x40
    if count > 0x10000 or names > 1 << 20:
        return None
    raw = f.read(count * size + names)
    if len(raw) != count * size + names:
        return None
    strings, data = raw[count * size:], at + 16 + len(raw)
    files = []
    for i in range(count):
        offset, length, start = struct.unpack_from('<QQI', raw, i * size)
        files.append((strings[start:strings.find(b'\0', start)].decode(errors='replace'), data + offset, length))
    return files


def metas(rom):
    """(kind, title ID, version) of each content meta in the game file."""
    with open(rom, 'rb') as f:
        files = table(f, 0, b'PFS0')
        if files is None:
            f.seek(0x100)
            if f.read(4) == b'HEAD':
                f.seek(0x130)
                root = table(f, struct.unpack('<Q', f.read(8))[0], b'HFS0') or []
                secure = [at for n, at, _ in root if n == 'secure']
                files = table(f, secure[0], b'HFS0') if secure else None
        if files is None:
            fail(f'{os.path.basename(rom)} is neither an NSP nor an XCI, nor nsz\'s NSZ or XCZ of one')
        found = []
        for meta, at, length in files:
            if not meta.lower().endswith('.cnmt.nca'):
                continue
            shutil.rmtree(tmp, ignore_errors=True)
            os.makedirs(tmp)
            f.seek(at)
            data = f.read(min(length, 1 << 24))
            with open(f'{tmp}/meta.nca', 'wb') as out:
                out.write(data)
            run = subprocess.run([hactool, '-k', keys, '--disablekeywarns', '--suppresskeys', '-t', 'nca',
                                  f'--section0dir={tmp}/out', f'{tmp}/meta.nca'], capture_output=True, text=True,
                                 errors='replace')
            cnmt = glob.glob(f'{tmp}/out/*.cnmt')
            if len(cnmt) != 1 or os.path.getsize(cnmt[0]) < 0x20:
                said = re.sub('[0-9A-Fa-f]{32,}', '…', (run.stderr.strip() or 'no content meta in it').splitlines()[-1])
                needs = re.search(r'Master Key Revision: +0x([0-9A-F]+)', run.stdout)
                needs = f': it needs master_key_{int(needs[1], 16):02x}, which the console keys may not have' if needs else ''
                fail(f'hactool can\'t read the content meta of {os.path.basename(rom)} ({said}){needs}')
            found.append(struct.unpack_from('<QIB', open(cnmt[0], 'rb').read()))
    shutil.rmtree(tmp, ignore_errors=True)
    if not found:
        fail(f'{os.path.basename(rom)} holds no content meta: it is no Switch game file')
    return [(kind, tid, ver) for tid, ver, kind in found]


def holds(found):
    return ', '.join(f'{KINDS.get(kind, f"content of kind {kind:#x}")} {tid:016X} version {ver}' for kind, tid, ver in found)


have = {}
want = f'{name} ({title}), its update {display} ({update:016X}, version {version}) or its DLC'
for rom in sys.argv[8:]:
    who, found = os.path.basename(rom), metas(rom)
    game = [ver for kind, tid, ver in found if kind == 0x80 and tid == base]
    patch = [ver for kind, tid, ver in found if kind == 0x81 and tid == update]
    dlc = [tid for kind, tid, ver in found if kind == 0x82 and (tid & ~0xFFF) - 0x1000 == base]
    if game:   # a game card's may hold an update too: it's the game all the same
        role = 0x80
        if game != [0]:
            fail(f'{who} holds {name} at version {game[0]}, not version 0, which nxnative takes for the base game')
    elif patch:
        role = 0x81
        if version not in patch:
            fail(f'{who} holds {name}\'s update at version {", ".join(map(str, patch))}, not {display} (version '
                 f'{version}), the one the game profile packs')
    elif dlc:
        role = 0x82
    else:
        fail(f'{who} holds {holds(found)}, not {want}')
    if role in have and role != 0x82:
        fail(f'{have[role]} and {who} both hold the {KINDS[role]}')
    have[role] = who
    print(f'{who}: {name}, {KINDS[role]}' + (f' {display}' if role == 0x81 else f' {dlc[0]:016X}' if role == 0x82 else ''))
for role in (0x80, 0x81):
    if role not in have:
        fail(f'no game file holds the {KINDS[role]}: the Port needs {name} ({title}) and its update {display} '
             f'({update:016X}, version {version})')
EOF
}

# unpack_nsz <nsz or xcz> <keys> <folder>: the NSP or XCI that nsz's NSZ or XCZ was made from, written into the folder
# by nsz's own decompressor, the one nsz -D runs. nsz's key table gets the console keys as they are (its key loader
# also wants the ocean and system key area sources, which the standard form leaves out and games don't use): with them
# nsz checks each NCA against the content meta and says so, VERIFIED or CORRUPTED, and goes on, as nsz -D does.
# nx_extract's hash check then stops on a damaged one.
unpack_nsz() {
    rm -rf "$3"
    mkdir -p "$3"
    "$deps/python/bin/python3" -I - "$@" <<'EOF'
import sys
from pathlib import Path
from nsz.Decompressor import decompress
from nsz.nut import Keys

source, keys, folder = sys.argv[1:4]
for line in open(keys, encoding='utf-8'):
    key, _, value = line.partition('=')
    if value.strip():
        Keys.keys[key.strip()] = value.strip()
decompress(Path(source), Path(folder), False)
EOF
}

build() {
    dotnet_environment
    export PATH=$prefix/bin:$deps/python/bin:$PATH USER=frontport
    local py=$deps/python/bin/python3
    build_tools
    make_xcrun

    # The version the game profile was brought up on: the one the update must be, and the one the Catalog accepts.
    local profile version display
    profile=$(DM_GAME=$title "$py" -I - "$nx/dm/games" <<'EOF'
import os, sys
sys.path.insert(0, sys.argv[1]); import game
g = game.load(os.environ['DM_GAME']); print(g.get('package')[1:], g.builds()[g.get('package')]['display'])
EOF
)
    version=${profile%% *} display=${profile#* }

    # The NSP folder: the script keeps its work in <title ID>_build/ there, and later builds reuse its extraction,
    # rewritten modules and shaders while their inputs are the same. The Build Assets get clones of the game files,
    # which take no space while both are kept; uninstalling removes Builds/<port>. An NSZ's NSP or an XCZ's XCI is kept
    # in unpacked/ under the ROM's hash, so the script finds the same file next time.
    local nsp=$work/nsp unpacked=$work/unpacked keys="" rom made kept=" " games=()
    mkdir -p "$nsp" "$unpacked"
    find "$nsp" -maxdepth 1 -type l -delete
    for rom in "$FRONTPORT_ROMS"/*; do
        [ -f "$rom" ] || continue
        case "$rom" in
            *.keys) keys=$rom ;;
            *.nsp | *.xci) games+=("$rom") ;;
            *.nsz) games+=("$rom") kept+="$(basename "${rom%.*}").nsp " ;;
            *.xcz) games+=("$rom") kept+="$(basename "${rom%.*}").xci " ;;
        esac
    done
    # First those of ROMs no longer used, and any left half made, so they don't hold the space a new one needs.
    for rom in "$unpacked"/*; do
        [ -e "$rom" ] || continue
        [[ "$kept" == *" $(basename "$rom") "* ]] || rm -rf "$rom"
    done
    if [ ${#games[@]} -gt 0 ]; then
        [ -n "$keys" ] || fail "no console keys among the Build-Stage ROMs"
        echo "==> Checking the game files"
        check_games "$keys" "$version" "$display" "${games[@]}"
    fi
    for rom in ${games[@]+"${games[@]}"}; do
        case "$rom" in
            *.nsp | *.xci) ln -s "$rom" "$nsp/$(basename "$rom")" ;;
            *)
                made=$(basename "${rom%.*}").$([[ "$rom" == *.nsz ]] && echo nsp || echo xci)
                if [ ! -f "$unpacked/$made" ]; then
                    echo "==> Decompressing $(basename "$rom")"
                    unpack_nsz "$rom" "$keys" "$unpacked/partial"
                    [ -f "$unpacked/partial/$made" ] || fail "nsz made no $made of $(basename "$rom")"
                    mv "$unpacked/partial/$made" "$unpacked/$made"
                    rm -rf "$unpacked/partial"
                fi
                ln -s "$unpacked/$made" "$nsp/$made"
                ;;
        esac
    done

    local font out game_files=""
    if [ -n "$(find "$nsp" -maxdepth 1 -type l)" ]; then
        echo "==> Running nxnative's NSP script"
        out=$work/nsp-script.log
        "$py" "$nx/scripts/build_ipa_from_nsp.py" "$nsp" -k "$keys" --platform mac --progress lines | tee "$out"
        game_files=$work/game-files.sh
        # The last line the script prints is the command that runs the game, built from its own paths.
        "$py" -I - "$out" >"$game_files" <<'EOF'
import shlex, sys
line = [l for l in open(sys.argv[1], encoding='utf-8', errors='replace') if l.startswith('cd ')][-1]
words = shlex.split(line)
env = dict(w.split('=', 1) for w in words[3:-2] if '=' in w)
for key, name in (('DM_ROMFS', 'romfs'), ('DM_MSL_DIR', 'msl'), ('DM_FONT_DIR', 'font'), ('DM_NVN_SHMAP', 'shmap'), ('DM_AOC_DIR', 'aoc')):
    print(f'{name}={shlex.quote(env.get(key, ""))}')
print(f'patched={shlex.quote(words[-1])}')
EOF
        # shellcheck disable=SC1090
        . "$game_files"
        font=$font/nintendo_ext.ttf
    else
        echo "==> No NSP given: building the app alone"
        # The chain version header, as the NSP script writes it before building a host.
        "$py" "$nx/dm/gfx/tools/dmsh_chain.py" --header >/dev/null
        mkdir -p "$work/font"
        font=$work/font/nintendo_ext.ttf
        "$py" "$nx/dm/tools/make_ext_font.py" "$font"
    fi

    echo "==> Making the app"
    local bundle=$FRONTPORT_OUT/$app_name.app plist
    plist=$bundle/Contents/Info.plist
    mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources/font"
    cp "$font" "$bundle/Contents/Resources/font/nintendo_ext.ttf"
    build_executable "$bundle/Contents/MacOS/nxnative"
    plutil -create xml1 "$plist"
    plutil -insert CFBundleExecutable -string nxnative "$plist"
    plutil -insert CFBundleIdentifier -string "dev.frontport.port.$FRONTPORT_PORT" "$plist"
    plutil -insert CFBundleName -string "$app_name" "$plist"
    plutil -insert CFBundlePackageType -string APPL "$plist"
    plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "$plist"
    plutil -insert CFBundleShortVersionString -string "$display" "$plist"
    plutil -insert CFBundleVersion -string "$display" "$plist"
    plutil -insert LSMinimumSystemVersion -string 26.0 "$plist"
    plutil -insert LSApplicationCategoryType -string public.app-category.games "$plist"
    plutil -insert NSHighResolutionCapable -bool true "$plist"

    [ -n "$game_files" ] || return 0
    # The game's own icon, next to its RomFS, as nxnative's iPhone app uses it.
    if [ -f "$(dirname "$romfs")/icon.jpg" ]; then
        make_icon "$(dirname "$romfs")/icon.jpg" "$bundle/Contents/Resources/nxnative.icns"
        plutil -insert CFBundleIconFile -string nxnative "$plist"
    fi

    echo "==> Gathering the game files"
    local assets=$FRONTPORT_OUT/assets
    mkdir -p "$assets/shaders" "$assets/profile"
    cp -cR "$romfs" "$assets/romfs"
    cp -cR "$patched" "$assets/patched"
    cp -cR "$msl"/b-* "$assets/shaders/"
    [ -z "$shmap" ] || cp -c "$(dirname "$shmap")"/*.tsv "$assets/profile/"
    [ -z "$aoc" ] || cp -cR "$aoc" "$assets/aoc"
    echo "$FRONTPORT_REF" >"$assets/nxnative.txt"
}

case "$step" in
    fetch) fetch ;;
    build) build ;;
    *) fail "unknown step $step" ;;
esac
