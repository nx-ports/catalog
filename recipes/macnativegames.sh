#!/bin/bash
# Frontport Recipe: MacNativeGames (ly05010419/MacNativeGames), Tears of the Kingdom's own arm64 code running natively,
# with the Switch's system answered by a host and its NVN graphics rebuilt on Metal.
# Contract: catalog/recipes/README.md. Invoked as `macnativegames.sh fetch`, then `macnativegames.sh build`.
#
# Upstream's build_app.py makes the app from the user's NSPs, keys and firmware. Build runs its steps, by importing it,
# up to the files the app is made of, then makes the app its own way:
# - One executable. Upstream's launcher (app/launcher.m, Contents/MacOS/TOTK) execs the game, a second program; AppKit
#   aborts its check-in in a program the app execs, which Frontport signs with `inherit` (as nxnative's did). So the
#   game is linked into the launcher, its main renamed totk_main, and the launcher calls it instead of execv.
# - Build Assets: the game folder upstream keeps at Contents/Resources/totk (rewritten code modules, RomFS image and
#   overlays, shared fonts, startup shaders and their Metal libraries), left at $FRONTPORT_OUT/assets for the Catalog's
#   buildAssets.path. The game finds its files from where it believes it runs, totk/build/totk-native: it's compiled
#   with _NSGetExecutablePath renamed to frontport_executable_path, which says so.
# - Programs in the app. The sandbox runs programs only from inside the app, so spirv-cross and the shader translator,
#   which the game starts, go in Contents/Helpers, where a patch points the game.
# The game's binary carries tables made from the game's code (build/<version>/runtime_tables.h), so the app isn't the
# same for every ROM; a build without ROMs makes it from the tables an earlier build left in Builds/<port>/work.
#
# Before those steps, build reads each game file's content meta, which hactool decrypts, and stops unless it holds the
# game or its update at the version the Port plays. Frontport keeps nsz's NSZ and XCZ files compressed: build makes
# each into the NSP or XCI it was made from with nsz's own decompressor, the one nsz -D runs (nsz -D itself starts a
# multiprocessing manager, whose Unix socket the build sandbox refuses), and keeps it in Builds/<port>/work/unpacked.
#
# Upstream needs Homebrew's opus, libvpx and Python 3.14 and pip's packages, and fetches SPIRV-Cross and hactool while
# it builds. This fetches each pinned instead (a standalone Python 3.14, wheels, sources built into the prefix). Xcode's
# Metal toolchain must be installed (xcodebuild -downloadComponent MetalToolchain): $FRONTPORT_METAL is its bin folder,
# and every startup shader is compiled into the Build Assets, never into macOS's own cache.
set -euo pipefail

step=${1:?usage: macnativegames.sh fetch|build}
src=$FRONTPORT_SRC
work=$(dirname "$src")                 # Builds/<port>: writable during build, kept between builds
mng=$src/MacNativeGames
deps=$src/deps
prefix=$work/prefix                    # opus and libvpx, reused while their pins and options don't change
made=$work/work                        # build_app.py's work folder: what it made, reused while still right
export GIT_CEILING_DIRECTORIES=$work

fail() {
    echo "error: $*" >&2
    exit 1
}

[ "$FRONTPORT_PORT" = macnativegames-totk ] || fail "Port $FRONTPORT_PORT names no game this Recipe builds (macnativegames-totk)"

# name sha256 url. Archives unpack into deps/<name>; wheels are kept in deps/wheels. SPIRV-Cross and hactool are the
# commits build_app.py pins (SPIRV_CROSS, HACTOOL); build checks that it still does.
downloads="
python 226d696642a8a53d03b4d5b255b1c319b1575a6d44bd723a953c9f507755e36a https://github.com/astral-sh/python-build-standalone/releases/download/20261021/cpython-3.14.9%2B20261021-aarch64-apple-darwin-install_only.tar.gz
opus 6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1 https://downloads.xiph.org/releases/opus/opus-1.6.1.tar.gz
libvpx 073bd6202e4c55c8cb759abbb123aecd4cc8d99f52ba27af790178cfb1108423 https://github.com/webmproject/libvpx/archive/6df3ec34557879fff673706f4a1d9fbd0f3a6f0e.tar.gz
SPIRV-Cross b99db6ee6182dbeb102257e755bf6d4978c23dcfd3329033304779279bc27212 https://github.com/KhronosGroup/SPIRV-Cross/archive/aa217aeb6c9f0ace7a0ab233b28807edf45eb165.tar.gz
hactool f7148daad624ba909f5ae253210734b1a0ce19e89a7914b6cf71401f7134ebbc https://github.com/SciresM/hactool/archive/1d64a83450e025622f3468c28fc4164dad2c5ef6.tar.gz
cryptography-50.0.2-cp311-abi3-macosx_11_0_arm64.whl fa8f5efb344d6908a1ce62f4a24e2e5780f825d6f53f5f50ec5ffacac72936cb https://files.pythonhosted.org/packages/e5/56/d194340cc4a57535e82e1bee9e89667ac4b7c13b5d3f59686deae3094dd5/cryptography-50.0.2-cp311-abi3-macosx_11_0_arm64.whl
cffi-2.1.1-cp314-cp314-macosx_11_0_arm64.whl 661c298b4821edebead0c91edd2b00374d67ad7c5a1f7a91d4442633b79d6a72 https://files.pythonhosted.org/packages/b3/a9/9db617d05d7367c1ad0ab00b3aa6e6f9281edd689b4ee9ea0e5a84e89c97/cffi-2.1.1-cp314-cp314-macosx_11_0_arm64.whl
pycparser-3.12-py3-none-any.whl a076f3f489b39b43ed13563a1dafe42447445bec2e294154ec5c57fcdda4c85e https://files.pythonhosted.org/packages/b6/ae/315bbeee126a769cbde43cf4908acb4b40408d8bf8bbf334dd7368d8dadf/pycparser-3.12-py3-none-any.whl
lz4-4.4.5-cp314-cp314-macosx_11_0_arm64.whl c8e71b14938082ebaf78144f3b3917ac715f72d14c076f384a4c062df96f9df6 https://files.pythonhosted.org/packages/b6/cb/bfead8f437741ce51e14b3c7d404e3a1f6b409c440bad9b8f3945d4c40a7/lz4-4.4.5-cp314-cp314-macosx_11_0_arm64.whl
capstone-5.0.9-py3-none-macosx_11_0_arm64.whl fc269c5082e17d7f9f265cd6980e2fdc6ab572df913951d76db0357e06b8001d https://files.pythonhosted.org/packages/42/9a/4eecfbc94961cda70301fd13de69042be1943bee456e37bc1369840601b1/capstone-5.0.9-py3-none-macosx_11_0_arm64.whl
nsz-5.0.0-py3-none-any.whl b3698cab8d7720aed056a0290017ff60a989d8343b7bb9c3c161ab137ec03965 https://files.pythonhosted.org/packages/85/7f/e11c738d92ffa58116184b443636b27c4cdefc0a7d73e5eacff1c9e3b6dd/nsz-5.0.0-py3-none-any.whl
pycryptodome-4.2.0-cp39-abi3-macosx_10_9_universal2.whl 3e430168f767ecec60c1f850df4abbd0b9f94786b9cc8041a00e976f6d5190c6 https://files.pythonhosted.org/packages/41/4c/954a9a1451f7bcc89d66db39bf6499ef5701e8ff35b6c898c659a7ec8546/pycryptodome-4.2.0-cp39-abi3-macosx_10_9_universal2.whl
zstandard-0.25.0-cp314-cp314-macosx_11_0_arm64.whl 05df5136bc5a011f33cd25bc9f506e7426c0c9b3f9954f056831ce68f3b6689f https://files.pythonhosted.org/packages/8d/09/d0a2a14fc3439c5f874042dca72a79c70a532090b7ba0003be73fee37ae2/zstandard-0.25.0-cp314-cp314-macosx_11_0_arm64.whl
enlighten-1.14.1-py2.py3-none-any.whl 5fbd0c959ca1644034c41bb0ace5db19c9852cf9d721b6103f5f130663c57be8 https://files.pythonhosted.org/packages/73/1e/244bb2fc5713ad21ae9f9012067f6432c682593816c6a45372c24f5a7d61/enlighten-1.14.1-py2.py3-none-any.whl
blessed-1.52.0-py3-none-any.whl 1936f421f3feb130035a4629e6477d1432e33b2674ab2b9841292c74d479eac2 https://files.pythonhosted.org/packages/29/1f/88e64e3b4a8299fcc47dd0db35276ca21c18fadad4e8eb25afad546404c6/blessed-1.52.0-py3-none-any.whl
jinxed-2.1.0-py2.py3-none-any.whl 43b802d18b70e405d410fb66eb2837d1101e7e5ea922e666507bb43f34d11d09 https://files.pythonhosted.org/packages/f1/1d/0a6be99b69bb448448403a45a241aff0dca751832ae54f027ed940d2eb52/jinxed-2.1.0-py2.py3-none-any.whl
wcwidth-0.9.4-cp310-abi3-macosx_11_0_arm64.whl f279f32c8e206a9092fa350e53ca0c2bd8072e45b1c9fd31bb6d476b59b591c4 https://files.pythonhosted.org/packages/04/e9/dfdca30ca36c472de3e260406dee29fc108499ec590c63b3fe279887ee9d/wcwidth-0.9.4-cp310-abi3-macosx_11_0_arm64.whl
prefixed-0.9.0-py2.py3-none-any.whl 3cdb74bfc4cf0aba28f3574662b13afdcac27c463dcbef320fe5d03f4c5fbca8 https://files.pythonhosted.org/packages/c3/61/d9957a0ed189ac8a89075c59c97588fb1c77e51d8d44a26f5cdf001d260c/prefixed-0.9.0-py2.py3-none-any.whl
"

# patch_text <file> <count> <old> <new>: replaces old, which must appear exactly count times (+: at least once), so a
# changed upstream fails here.
patch_text() {
    "$deps/python/bin/python3" -I - "$@" <<'EOF'
import sys
path, count, old, new = sys.argv[1:5]
text = open(path, encoding='utf-8').read()
if text.count(old) == 0 or count != '+' and text.count(old) != int(count):
    sys.exit(f'error: {path}: expected {count} of {old!r}, found {text.count(old)}: upstream changed')
open(path, 'w', encoding='utf-8').write(text.replace(old, new))
EOF
}

fetch() {
    case "$FRONTPORT_REF" in
        [0-9a-f]*) [ ${#FRONTPORT_REF} -eq 40 ] || fail "pin MacNativeGames by its full commit, not $FRONTPORT_REF" ;;
        *) fail "pin MacNativeGames by its full commit, not $FRONTPORT_REF" ;;
    esac
    echo "==> Fetching MacNativeGames $FRONTPORT_REF"
    git init --quiet "$mng"
    git -C "$mng" fetch --quiet --depth 1 https://github.com/ly05010419/MacNativeGames.git "$FRONTPORT_REF"
    git -c advice.detachedHead=false -C "$mng" checkout --quiet FETCH_HEAD
    [ "$(git -C "$mng" rev-parse HEAD)" = "$FRONTPORT_REF" ] || fail "the fetched commit isn't $FRONTPORT_REF"

    mkdir -p "$deps/wheels"
    local name sha url file
    while read -r name sha url; do
        [ -n "$name" ] || continue
        echo "==> Downloading $name"
        file=$deps/$name.download
        curl -fsSL --retry 3 -o "$file" "$url"
        echo "$sha  $file" | shasum -a 256 -c --status - || fail "$name doesn't match its pinned sha256"
        case "$name" in
            *.whl) mv "$file" "$deps/wheels/$name" ;;
            *)
                mkdir -p "$deps/$name"
                tar -xzf "$file" -C "$deps/$name" --strip-components=1
                rm "$file"
                ;;
        esac
    done <<<"$downloads"

    echo "==> Patching MacNativeGames for the sandbox"
    local game=$mng/games/totk
    # opus and libvpx from the prefix instead of Homebrew's.
    patch_text "$game/Makefile" + /opt/homebrew/opt/opus "$prefix"
    patch_text "$game/Makefile" + /opt/homebrew/opt/libvpx "$prefix"
    # The launcher runs the game linked into it, from where Frontport puts it, instead of execing a second program.
    patch_text "$game/app/launcher.m" 1 \
        'NSString *binary = [root stringByAppendingPathComponent:@"build/totk-native"];' \
        'NSString *binary = NSBundle.mainBundle.executablePath;   // Frontport: the game is linked into this program'
    patch_text "$game/app/launcher.m" 1 \
        'execv(arguments[0], arguments);' \
        'exit(totk_main(3, (char **)arguments));   // Frontport: the game is linked in, its main renamed'
    patch_text "$game/app/launcher.m" 1 \
        'int main(int argc, char **argv) {' \
        'int totk_main(int argc, char **argv);   // Frontport: the game'"'"'s main, renamed
int main(int argc, char **argv) {'
    # The startup shaders sit in the Build Assets, outside the app: read them in place, as upstream's sealed app does.
    patch_text "$game/app/launcher.m" 1 \
        'setenv("TOTK_SHARED_FONTS", "extracted/firmware/shared-fonts", 1);' \
        'setenv("TOTK_SHARED_FONTS", "extracted/firmware/shared-fonts", 1);
        setenv("TOTK_SHADER_SEED_IN_PLACE", "1", 0);   // Frontport: the Build Assets are read-only, made by Frontport'
    # The game starts the shader translator and spirv-cross; the sandbox runs them only from inside the app.
    patch_text "$game/third_party/d2r_gfx/gfx/nvn/totk_shader_rt.m" 1 \
        'NSString *sc = [r stringByAppendingString:@"/build/spirv-cross/spirv-cross"];' \
        'NSString *sc = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Contents/Helpers/spirv-cross"];   // Frontport'
    patch_text "$game/third_party/d2r_gfx/gfx/nvn/totk_shader_rt.m" 1 \
        'NSString *native = [r stringByAppendingString:@"/build/shader-service/totk_xlate"];' \
        'NSString *native = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Contents/Helpers/totk_xlate"];   // Frontport'
}

# libvpx's decoders only: the game plays its movies with them. Its compiler is clang itself, since xcrun can't keep its
# cache in the build sandbox and looks the compiler up again for every file.
vpx_options="--enable-static --disable-shared --disable-examples --disable-tools --disable-docs --disable-unit-tests
    --disable-vp8-encoder --disable-vp9-encoder --enable-vp9-highbitdepth --enable-pic"

# opus and libvpx into the prefix, static, rebuilt only when their pins or options change.
build_libs() {
    local stamp=$prefix/stamp want
    want=$( (echo "$downloads" | grep -E '^(opus|libvpx) '; echo "$vpx_options") | shasum -a 256 | cut -d' ' -f1)
    if [ -f "$prefix/lib/libopus.a" ] && [ -f "$prefix/lib/libvpx.a" ] && [ "$(cat "$stamp" 2>/dev/null)" = "$want" ]; then
        return
    fi
    rm -rf "$prefix" "$work/build"
    echo "==> Building opus"
    cmake -S "$deps/opus" -B "$work/build/opus" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_INSTALL_PREFIX="$prefix" -DBUILD_SHARED_LIBS=OFF -DOPUS_BUILD_TESTING=OFF -DOPUS_BUILD_PROGRAMS=OFF
    cmake --build "$work/build/opus" -j "$FRONTPORT_JOBS"
    cmake --install "$work/build/opus" >/dev/null
    echo "==> Building libvpx"
    mkdir -p "$work/build/libvpx"
    # shellcheck disable=SC2086
    (cd "$work/build/libvpx" && CC=clang CXX=clang++ "$deps/libvpx/configure" --prefix="$prefix" \
        --target=arm64-darwin23-gcc $vpx_options >/dev/null)
    make -C "$work/build/libvpx" -j "$FRONTPORT_JOBS" >/dev/null
    make -C "$work/build/libvpx" install >/dev/null
    echo "$want" >"$stamp"
}

# The game's view of where it runs: upstream's app starts it as Contents/Resources/totk/build/totk-native, and it finds
# its files from there (its shader cache and libraries, the folder of its pipeline lists). Linked into the app's
# executable, it is told the same; every call to _NSGetExecutablePath in its sources is compiled as a call to this.
write_executable_path() {
    cat >"$1" <<'EOF'
// Added by Frontport's MacNativeGames Recipe: where the game would be in upstream's app.
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <string.h>

int frontport_executable_path(char *buf, uint32_t *size) {
    char exe[PATH_MAX]; uint32_t n = sizeof exe;
    if (_NSGetExecutablePath(exe, &n)) return -1;
    for (int i = 0; i < 2; i++) { char *slash = strrchr(exe, '/'); if (!slash) return -1; *slash = 0; }   // Contents
    int need = snprintf(NULL, 0, "%s/Resources/totk/build/totk-native", exe) + 1;
    if ((uint32_t)need > *size) { *size = (uint32_t)need; return -1; }
    snprintf(buf, *size, "%s/Resources/totk/build/totk-native", exe);
    return 0;
}
EOF
}

# make_icon <image> <icns>: the game's icon (the 256-pixel JPEG in its control data) as an app icon. sips and iconutil
# need LaunchServices, which the build sandbox doesn't offer, but ImageIO itself works there: a small tool draws it as a
# rounded square on macOS's 1024-pixel icon grid, and the icon holds that PNG as is.
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

# The steps of build_app.py's main for a base game and an update, run from its own functions, then the app and the
# Build Assets as this Recipe makes them. Arguments: the app to make, the Build Assets folder, and the ROMs (none for
# the app alone).
write_driver() {
    cat >"$1" <<'EOF'
# Added by Frontport's MacNativeGames Recipe: build_app.py's steps, then the app as Frontport runs it.
import json, os, plistlib, re, shutil, struct, subprocess, sys
from pathlib import Path

repo, work, deps, app, assets = (Path(p) for p in sys.argv[1:6])
roms = [Path(p) for p in sys.argv[6:]]
sys.path.insert(0, str(repo))
import build_app as b

TOTK, UPDATE = '0100F2C0115B6000', '0100F2C0115B6800'
# The update the Port plays, 1.4.3, of those upstream makes: the one the Catalog lists.
PLAYS = 'v143'
logs = work / 'logs'
env = dict(os.environ)
jobs = os.environ['FRONTPORT_JOBS']


def stage(what):
    print(f'==> {what}', flush=True)


def report_error(kind, error, traceback):
    if issubclass(kind, b.BuildError):
        print(f'error: {error}', file=sys.stderr)   # the exit status is 1 all the same
    else:
        sys.__excepthook__(kind, error, traceback)


sys.excepthook = report_error


# The sources build_app.py would clone, as fetch downloaded them. A pin of its own that differs stops the build.
fetched = {b.SPIRV_CROSS: deps / 'SPIRV-Cross', b.HACTOOL: deps / 'hactool'}


def git_fetch(url, commit, dst, log):
    if (url, commit) not in fetched:
        raise b.BuildError(f'build_app.py now pins {url} at {commit}: update the Recipe\'s download')
    stamp = dst / '.frontport-commit'
    if stamp.is_file() and stamp.read_text() == commit:
        return
    if dst.is_symlink():
        dst.unlink()
    elif dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(fetched[(url, commit)], dst, symlinks=True)
    stamp.write_text(commit)


# Xcode's Metal toolchain from $FRONTPORT_METAL, with its module cache in $TMPDIR.
def metal_compiler():
    metal = Path(os.environ['FRONTPORT_METAL']) / 'metal'
    version = subprocess.run([metal, '--version'], capture_output=True, text=True, check=True)
    return str(metal), version.stdout.splitlines()[0], env


b.git_fetch = git_fetch
b.metal_compiler = metal_compiler
b.METAL_FLAGS = [*b.METAL_FLAGS, f'-fmodules-cache-path={os.environ["TMPDIR"]}/metal-modules']

# The files of a PFS0 (an NSP or NSZ) or an HFS0 (a partition of an XCI or XCZ) at `at`, as (name, offset, size).
def partition(f, at, magic):
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


# (kind, title ID, version) of each content meta in a game file. Its meta NCA, which an NSZ and an XCZ keep as it is, is
# copied out, hactool decrypts it, and this reads the content meta hactool writes: its title ID, version and kind.
def content_metas(hactool, keys, rom):
    tmp = Path(os.environ['TMPDIR']) / 'meta'
    with rom.open('rb') as f:
        files = partition(f, 0, b'PFS0')
        if files is None:
            f.seek(0x100)
            if f.read(4) == b'HEAD':
                f.seek(0x130)
                root = partition(f, struct.unpack('<Q', f.read(8))[0], b'HFS0') or []
                secure = [at for n, at, _ in root if n == 'secure']
                files = partition(f, secure[0], b'HFS0') if secure else None
        if files is None:
            raise b.BuildError(f'{rom.name} is neither an NSP nor an XCI, nor nsz\'s NSZ or XCZ of one')
        found = []
        for meta, at, length in files:
            if not meta.lower().endswith('.cnmt.nca'):
                continue
            shutil.rmtree(tmp, ignore_errors=True)
            tmp.mkdir()
            f.seek(at)
            (tmp / 'meta.nca').write_bytes(f.read(min(length, 1 << 24)))
            run = subprocess.run([hactool, '-k', keys, '--disablekeywarns', '--suppresskeys', '-t', 'nca',
                                  f'--section0dir={tmp}/out', tmp / 'meta.nca'], capture_output=True, text=True,
                                 errors='replace')
            cnmt = list(tmp.glob('out/*.cnmt'))
            if len(cnmt) != 1 or cnmt[0].stat().st_size < 0x20:
                said = re.sub('[0-9A-Fa-f]{32,}', '…', (run.stderr.strip() or 'no content meta in it').splitlines()[-1])
                needs = re.search(r'Master Key Revision: +0x([0-9A-F]+)', run.stdout)
                needs = f': it needs master_key_{int(needs[1], 16):02x}, which the console keys may not have' if needs else ''
                raise b.BuildError(f'hactool can\'t read the content meta of {rom.name} ({said}){needs}')
            found.append(struct.unpack_from('<QIB', cnmt[0].read_bytes()))
    shutil.rmtree(tmp, ignore_errors=True)
    if not found:
        raise b.BuildError(f'{rom.name} holds no content meta: it is no Switch game file')
    return [(kind, tid, ver) for tid, ver, kind in found]


# The base game and the update among the game files, by their content meta: the game at version 0 (1.0.0) and its update
# at the version the Port plays. Seconds, before any NSZ is decompressed or any code extracted; upstream's
# identify_update then checks the update's code by its hashes.
def check_games(hactool, keys, games):
    kinds = {0x80: 'base game', 0x81: 'update', 0x82: 'DLC'}
    supported = {b.VERSIONS[v]['version']: b.VERSIONS[v]['display_version'] for v in b.UPDATES if v == PLAYS}
    named = [f'{d} (version {v})' for v, d in supported.items()]
    updates = ' or '.join(named)
    want = f'{b.APP_NAME} ({TOTK}) {{}} its update ({UPDATE}) at {updates}'
    have = {}
    for rom in games:
        found = content_metas(hactool, keys, rom)
        game = [ver for kind, tid, ver in found if kind == 0x80 and f'{tid:016X}' == TOTK]
        patch = [ver for kind, tid, ver in found if kind == 0x81 and f'{tid:016X}' == UPDATE]
        if game:   # a game card's may hold an update too: it's the game all the same
            role = 0x80
            if game != [b.VERSIONS['v0']['version']]:
                raise b.BuildError(f'{rom.name} holds {b.APP_NAME} at version {game[0]}, not {b.VERSIONS["v0"]["display_version"]} '
                                   f'(version {b.VERSIONS["v0"]["version"]}), the base game upstream supports')
        elif patch:
            role = 0x81
            if not set(patch) & set(supported):
                raise b.BuildError(f'{rom.name} holds the update at version {", ".join(map(str, patch))}, not {updates}, the one '
                                   f'the Port plays')
        else:
            held = ', '.join(f'{kinds.get(kind, f"content of kind {kind:#x}")} {tid:016X} version {ver}' for kind, tid, ver in found)
            raise b.BuildError(f'{rom.name} holds {held}, not {want.format("or")}')
        if role in have:
            raise b.BuildError(f'{have[role].name} and {rom.name} both hold the {kinds[role]}')
        have[role] = rom
        print(f'{rom.name}: {b.APP_NAME}, ' + ('base game' if role == 0x80 else
                                               f'update {supported[next(v for v in patch if v in supported)]}'), flush=True)
    for role in (0x80, 0x81):
        if role not in have:
            raise b.BuildError(f'no game file holds the {kinds[role]}: the Port needs {want.format("and")}')
    return have[0x80], have[0x81]


# Frontport keeps the keys every console shares: the sources and the master keys. Upstream reads the keys made from
# them, each title key's key and each key area key, straight from prod.keys, so hactool makes them (-t keygen), into a
# private file in $TMPDIR, which every build starts empty. Never printed or logged.
def derive_keys(hactool, standard, keys):
    made = subprocess.run([hactool, '-t', 'keygen', '-k', standard], capture_output=True, text=True, errors='replace')
    lines = [line for line in made.stdout.splitlines() if re.fullmatch(r'[0-9a-z_]+ *= *[0-9A-F]+', line)]
    if made.returncode or not any(line.startswith('key_area_key_application_') for line in lines):
        raise b.BuildError(f'hactool made no keys from the console keys (exit {made.returncode})')
    with open(os.open(keys, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as f:
        f.write('\n'.join(lines) + '\n')


# nsz's NSZ or XCZ as the NSP or XCI it was made from, by nsz's own decompressor, the one nsz -D runs, kept in
# work/unpacked under the ROM's hash for the next build. nsz's key table gets the console keys as they are (its key
# loader also wants the ocean and system key area sources, which the standard form leaves out and games don't use): with
# them nsz checks each NCA against the content meta and says so in its log, VERIFIED or CORRUPTED, and goes on, as
# nsz -D does; upstream's hash checks of the code and the RomFS then stop on a damaged one.
UNPACK = """
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
"""
unpacked = work / 'unpacked'
COMPRESSED = {'.nsz': '.nsp', '.xcz': '.xci'}


def unpack(rom, standard):
    if rom.suffix not in COMPRESSED:
        return rom
    made = unpacked / (rom.stem + COMPRESSED[rom.suffix])
    if not made.is_file():
        stage(f'Decompressing {rom.name}')
        partial = unpacked / 'partial'
        shutil.rmtree(partial, ignore_errors=True)
        partial.mkdir(parents=True)
        b.run([tree / '.venv/bin/python', '-I', '-c', UNPACK, rom, standard, partial], logs / f'nsz-{rom.stem}.log',
              cwd=tree)
        if not (partial / made.name).is_file():
            raise b.BuildError(f'nsz made no {made.name} of {rom.name}')
        (partial / made.name).rename(made)
        partial.rmdir()
    return made


stage('Preparing the work folder')
tree = b.prepare_work(work, Path(sys.executable), logs)
version = None
if roms:
    standard = next((r for r in roms if r.suffix == '.keys'), None)
    if standard is None:
        raise b.BuildError('no console keys among the Build-Stage ROMs')
    stage('Checking the game files')
    hactool = b.build_hactool(tree, logs)
    base, update = check_games(hactool, standard, [r for r in roms if r.suffix in ('.nsp', '.xci', *COMPRESSED)])
    keys = Path(os.environ['TMPDIR']) / 'prod.keys'
    derive_keys(hactool, standard, keys)
    # First those of ROMs no longer used, and any left half made, so they don't hold the space a new one needs.
    kept = {r.stem + COMPRESSED[r.suffix] for r in (base, update) if r.suffix in COMPRESSED}
    for old in unpacked.glob('*') if unpacked.is_dir() else []:
        if old.name not in kept:
            shutil.rmtree(old) if old.is_dir() else old.unlink()
    base, update = unpack(base, standard), unpack(update, standard)
    firmware = next(r for r in roms if r.suffix == '.folder')
    stage('Identifying the update')
    version, update = b.identify_update(tree, update, keys, logs)
    stage(f'Extracting and rewriting the code of {b.VERSIONS[version]["display_version"]}')
    b.step_code(tree, update, keys, env, logs, version=version)
    # The shared fonts, as step_data takes them from a firmware; the base game's own RomFS isn't needed for an update.
    fonts = tree / 'extracted/firmware/shared-fonts'
    if not b.fonts_valid(fonts):
        stage('Extracting the shared fonts')
        if fonts.exists():
            shutil.rmtree(fonts)
        b.run([tree / '.venv/bin/python', 'scripts/extract_shared_fonts.py', '--keys', keys, '--firmware', firmware,
               '--output', fonts], logs / 'shared_fonts.log', cwd=tree)
        b.validate_fonts(fonts)
    stage('Merging the RomFS of the base game and the update')
    b.step_update_data(tree, base, update, keys, logs, version=version)
    stage('Translating the startup shaders')
    b.step_shaders(tree, logs, version=version)
    stage('Compiling the startup shaders')
    b.step_shader_libs(tree, logs, version=version)
    (work / 'version.txt').write_text(version)
else:
    # The app alone: from what the last build with ROMs left, as the game's binary carries tables made from them.
    stamp = work / 'version.txt'
    version = stamp.read_text().strip() if stamp.is_file() else None
    if not version or not (tree / f'analysis/{version}-port/phase12-validation.json').is_file():
        raise b.BuildError('no ROMs, and no earlier build whose tables the game\'s binary could be made from: '
                           'add the ROMs and install again')

stage('Building the game')
expected = b.VERSIONS[version]
define = '-DTOTK_GAME_' + version.upper() + '=1'
native = ['NATIVE_OPT=-O2 -D_NSGetExecutablePath=frontport_executable_path']
target = f'build/totk-native-{version}'


def make_dry(*arguments):
    return subprocess.run(['make', *arguments, *native, target], cwd=tree, env=env, capture_output=True, text=True,
                          check=True).stdout.splitlines()


# What upstream's binary is made of (its graphics objects, the tables made from the game), then its one link line,
# which this links again with the launcher.
needs = [line.split(':', 1)[1].split() for line in make_dry('-p', '-n') if line.startswith(f'{target}: ')]
link = [line for line in make_dry('-n', '-B') if line.endswith(f' -o "{target}"')]
if len(needs) != 1 or len(link) != 1:
    raise b.BuildError(f'make gave no single rule for {target}')
b.run(['make', f'-j{jobs}', *native, *needs[0], 'build/pso_manifest.tsv', 'build/pso_title.tsv'], logs / 'runtime.log',
      cwd=tree, env=env)
exe = app / 'Contents/MacOS/TOTK'
exe.parent.mkdir(parents=True, exist_ok=True)
b.run(['clang', '-c', '-fobjc-arc', '-O2', '-Wall', '-Ithird_party/d2r_gfx/gfx/nvn', '-Iruntime', define, 'app/launcher.m',
       '-o', work / 'launcher.o'], logs / 'launcher.log', cwd=tree, env=env)
b.run(['clang', '-c', '-O2', '-Wall', work / 'executable_path.c', '-o', work / 'executable_path.o'],
      logs / 'executable_path.log', cwd=tree, env=env)
command = link[0][:-len(f' -o "{target}"')] + \
    f' -Dmain=totk_main "{work}/launcher.o" "{work}/executable_path.o" -framework AppKit -o "{exe}"'
b.run(['/bin/sh', '-c', command], logs / 'link.log', cwd=tree, env=env)
shutil.rmtree(exe.with_name('TOTK.dSYM'), ignore_errors=True)   # the debug symbols upstream's -g leaves beside it
helpers = app / 'Contents/Helpers'
helpers.mkdir(parents=True, exist_ok=True)
shutil.copy2(tree / 'build/spirv-cross/spirv-cross', helpers / 'spirv-cross')
shutil.copy2(tree / 'prebuilt/macos-arm64/totk_xlate', helpers / 'totk_xlate')

info = dict(CFBundleDevelopmentRegion='en', CFBundleExecutable='TOTK', CFBundleIdentifier=os.environ['FRONTPORT_BUNDLE_ID'],
            CFBundleName=b.APP_NAME, CFBundleDisplayName=b.APP_NAME, CFBundlePackageType='APPL',
            CFBundleShortVersionString=expected['display_version'], CFBundleVersion=str(expected['version'] + 1),
            LSMinimumSystemVersion='26.0', NSHighResolutionCapable=True,
            LSApplicationCategoryType='public.app-category.action-games', LSSupportsGameMode=True,
            GCSupportsControllerUserInteraction=True,
            CFBundleLocalizations=list(b.GAME_LANGUAGES) + (['pt-BR'] if version == 'v143' else []),
            MNGSourceCommit=os.environ['FRONTPORT_REF'][:7])
(app / 'Contents/PkgInfo').write_bytes(b'APPL????')
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
if not roms:
    sys.exit()

# The Build Assets: the game folder of upstream's app (step_app) without its programs, the RomFS image in place of its
# signed bundle.
stage('Gathering the game files')
seed = tree / f'build/shader-seed/{version}'
report = json.loads((seed / 'seed-manifest.json').read_text())
known = b.seed_digests(seed)
if (report['version'] != version or report['shaders'] < 8000 or not report['files'] or any(
        Path(name).name != name or b.seed_sha256(seed, name, known) != digest for name, digest in report['files'].items())):
    raise b.BuildError('the startup shaders were not prepared as build_app.py checks them')
files = [f'rewritten/{version}/{name}.patched.bin' for name in ('main', 'sdk', 'subsdk0')]
files += [f'extracted/{version}/romfs/romfs.bin', f'extracted/{version}/romfs/runtime-index.bin',
          'build/pso_manifest.tsv', 'build/pso_title.tsv']
for rel in files:
    b.clone(tree / rel, assets / rel)
for rel in (f'extracted/{version}/romfs-patches', f'extracted/{version}/romfs-patches-out', 'extracted/firmware/shared-fonts'):
    b.copy_tree(tree / rel, assets / rel)
b.copy_tree(seed, assets / 'build/shader-seed')
aliases = seed.with_name(seed.name + '.aliases.tsv')
if aliases.is_file():
    b.run([tree / '.venv/bin/python', 'scripts/shader_list.py', 'rename', aliases, assets / 'build/pso_manifest.tsv',
           assets / 'build/pso_title.tsv'], logs / 'shader-list-rename.log', cwd=tree)
for name, digest in report['files'].items():
    lib = tree / f'build/shader-libs/{digest}.metallib'
    if name.endswith('.metal') and lib.is_file():
        b.clone(lib, assets / 'build/shader-libs' / lib.name)

# The game's own icon from its control data, as extract_app_icon.py takes it, for make_icon.
b.run([tree / '.venv/bin/python', '-c', '''
import sys
from pathlib import Path
sys.path.insert(0, "scripts")
from extract_app_icon import LANGUAGES, control_nca
from extract_exefs import read_at
from extract_romfs import index_romfs
from extract_shared_fonts import Slice, load_keys, nca_romfs
game, keys, out = Path(sys.argv[1]), load_keys(Path(sys.argv[2])), Path(sys.argv[3])
image = out.with_name("control.romfs")
offset, tickets = control_nca(game, keys, "0100f2c0115b6000")
nca_romfs(Slice(game, offset), keys, image, tickets)
entries = {e["path"]: e for e in index_romfs(image)}
icon = next(entries[f"icon_{lang}.dat"] for lang in LANGUAGES if f"icon_{lang}.dat" in entries)
with image.open("rb") as f:
    out.write_bytes(read_at(f, icon["offset"], icon["size"]))
image.unlink()
''', base, keys, work / 'icon.jpg'], logs / 'app_icon.log', cwd=tree)
EOF
}

build() {
    [ -n "${FRONTPORT_METAL:-}" ] || fail "Xcode's Metal toolchain isn't installed: xcodebuild -downloadComponent MetalToolchain"
    build_libs
    # build_app.py's own virtual environment installs its packages from the fetched wheels.
    export PIP_NO_INDEX=1 PIP_FIND_LINKS=$deps/wheels PIP_DISABLE_PIP_VERSION_CHECK=1
    export FRONTPORT_BUNDLE_ID=dev.frontport.port.$FRONTPORT_PORT
    export PATH=$deps/python/bin:$PATH USER=frontport

    local roms=() rom
    for rom in "$FRONTPORT_ROMS"/*; do
        [ -e "$rom" ] && roms+=("$rom")
    done
    [ ${#roms[@]} -gt 0 ] || echo "==> No ROMs given: building the app alone"

    mkdir -p "$made"
    write_executable_path "$made/executable_path.c"
    write_driver "$work/frontport.py"
    local app=$FRONTPORT_OUT/"Tears of the Kingdom.app"
    rm -f "$made/icon.jpg"
    "$deps/python/bin/python3" -I "$work/frontport.py" "$mng" "$made" "$deps" "$app" "$FRONTPORT_OUT/assets" \
        ${roms[@]+"${roms[@]}"}
    if [ -f "$made/icon.jpg" ]; then
        mkdir -p "$app/Contents/Resources"
        make_icon "$made/icon.jpg" "$app/Contents/Resources/AppIcon.icns"
        plutil -insert CFBundleIconFile -string AppIcon "$app/Contents/Info.plist"
    fi
}

case "$step" in
    fetch) fetch ;;
    build) build ;;
    *) fail "unknown step $step" ;;
esac
