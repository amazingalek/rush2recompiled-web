#!/usr/bin/env bash
# Builds the web page (build-web/Rush2Recompiled.html, .js, .wasm, .data) from the US ROM, on Linux with emsdk active
# (N64Recomp-browser's README, Using it in a recomp, says what else: naga, spirv-opt, ccache), clang, Ninja and
# Python 3:
#
#   bash tools/build_web.sh <US ROM> [--prepare]
#   bash tools/build_web.sh --patches          step 1 alone: no ROM, and only git and CMake
#
# 1. The submodules the page needs (not ENet or miniupnpc: a page has no online play, src/online/online_web.cpp), and
#    their patches, from clean whenever lib/patches, lib/N64Recomp-browser or web/patches moved since the last time
#    (build-web-prep/web-patched records it): apply.cmake can't take a checkout from one version of its patches to
#    another. First Rush 2 Recompiled's own, lib/patches/<submodule>.patch, as the desktop build's CMakeLists.txt
#    applies them; then N64Recomp-browser's web support (lib/N64Recomp-browser/patches/apply.cmake, project by
#    project), but for the files where the two change the same lines: the web's change to those (web/patches/files.txt)
#    is web/patches/<project>.patch instead, made on top of Rush 2's from the N64Recomp-browser commit
#    web/patches/files.txt names, with what the web has changed in them since merged in by apply.cmake --since (only
#    a change that meets Rush 2's own lines stops the build, for another merge by hand).
#      rt64: what both add beside each other (Rush 2's present profiling mark beside the web's phase timer, its
#      Variable frame rate's timeline beside the offscreen workloads, its car reflection and ambient occlusion shaders
#      among the WGSL ones, its sampleTexture LOD arguments and coverage output beside the web's per-draw tiles and
#      decal depth, the coverage output left out of a page's shaders, as RasterPS.hlsl says); in TextureSampler.hlsli the web's texel loads keep Rush 2's rule that a generated mipmap level
#      and a region of a larger image are read by the tile, and that a filter neighbour past a region reads the
#      image's own next texel, and Rush 2's generated mipmaps and region texels are read through the web's draw texture
#      slots (sampleTileTextureGrad(), loadTileTexture()), not the desktop's texture array.
#      Beside Rush 2's disk shader cache, RasterShader takes the web's WGSL cache as well as Rush 2's compiled blobs,
#      RasterShaderCache has both's members, the shader threads are one on a page and Rush 2's at most 4 elsewhere, and
#      the web's replacement batch lock is held in Rush 2's applyReplacementDirectories, where packs are swapped in.
#      N64ModernRuntime: the VI thread's wait for the browser's frame inside Rush 2's not-turbo branch; in config.cpp
#      Rush 2's own parse of an option the file leaves out to its default, which does what the web's did.
#      RecompFrontend: the page's file picker beside Rush 2's Windows one, and the page's no-op in Rush 2's open_folder().
# 2. N64Recomp and RSPRecomp, built natively from the patched checkout: the page needs the code the web-patched
#    N64Recomp writes.
# 3. The ROM images (tools/extract.py) and the recompiled game and audio microcode (docs/BUILDING.md, steps 2 and 3).
# 4. The page, with emcmake, in build-web (CMakeLists.txt's EMSCRIPTEN parts). --prepare stops before it.
# --patches stops after step 1. N64Recomp-browser's CI runs it with its own checkout as lib/N64Recomp-browser and the
# submodules checked out, so a web change there that meets this port's own lines in a file left out is red where it is
# made: merge it into the patch by hand then.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
[[ $# -ge 1 ]] || { echo "usage: $0 <US ROM> [--prepare] | --patches" >&2; exit 2; }
patches_only=0
[[ "$1" == --patches ]] && patches_only=1
[[ $patches_only == 1 ]] || rom="$(realpath "$1")"
prepare_only=0
[[ "${2:-}" == --prepare ]] && prepare_only=1
cd "$root"
jobs="$(nproc)"
browser=lib/N64Recomp-browser
prep=build-web-prep
mkdir -p $prep

step() { printf '\n== %s\n' "$*"; }

# --- 1. Submodules and patches ---
step "Submodules"
[[ -f lib/rt64/CMakeLists.txt && -f lib/N64ModernRuntime/N64Recomp/CMakeLists.txt && -f lib/RecompFrontend/CMakeLists.txt &&
   -f $browser/patches/apply.cmake ]] ||
    git submodule update --init --recursive lib/rt64 lib/N64ModernRuntime lib/RecompFrontend $browser

step "Patches"
# <name> <checkout> [files left to web/patches/<name>.patch, merged from the commit files.txt names]
shared() { awk -v p="$1" '!/^#/ && $1 == p { printf "%s ", $2 }' web/patches/files.txt; }
merged_from="$(sed -n 's/^# merged from N64Recomp-browser //p' web/patches/files.txt)"
web_patches="rt64 lib/rt64 $(shared rt64)
plume lib/rt64/src/contrib/plume
hlslpp lib/rt64/src/contrib/hlslpp
N64ModernRuntime lib/N64ModernRuntime $(shared N64ModernRuntime)
N64Recomp lib/N64ModernRuntime/N64Recomp
RecompFrontend lib/RecompFrontend $(shared RecompFrontend)"
stamp="$(git -C $browser rev-parse HEAD) $( (cat lib/patches/*.patch web/patches/*.patch web/patches/files.txt; echo "$web_patches") | sha1sum | cut -c1-40)"
if [[ "$(cat $prep/web-patched 2> /dev/null)" != "$stamp" ]]; then
    for s in lib/rt64 lib/N64ModernRuntime lib/RecompFrontend; do
        git -C $s submodule foreach --recursive -q 'git reset -q --hard && git clean -fdq'
        git -C $s reset -q --hard && git -C $s clean -fdq
        rm -f "$(git -C $s rev-parse --path-format=absolute --git-dir)"/n64recomp-browser-*
    done
    for patch in lib/patches/*.patch; do  # a nested submodule's names its path with -- for / (CMakeLists.txt)
        sub="$(basename "$patch" .patch)"
        git -C "lib/${sub//--//}" apply --whitespace=nowarn "$root/$patch"
    done
    while read -r name checkout skip; do
        cmake -P $browser/patches/apply.cmake "$name" "$checkout" $skip
        [[ ! -f web/patches/$name.patch ]] || git -C "$checkout" apply --whitespace=nowarn "$root/web/patches/$name.patch"
        [[ -z "$skip" ]] || cmake -P $browser/patches/apply.cmake "$name" "$checkout" --since "$merged_from" $skip
    done <<< "$web_patches"
    echo "$stamp" > $prep/web-patched
fi

[[ $patches_only == 1 ]] && exit 0

# --- 2. N64Recomp and RSPRecomp ---
step "N64Recomp"
tools=$prep/tools
[[ -f $tools/build.ninja ]] || cmake -S lib/N64ModernRuntime/N64Recomp -B $tools -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ > /dev/null
ninja -C $tools N64RecompCLI RSPRecomp > /dev/null

# --- 3. The ROM images, the recompiled game and the audio microcode ---
step "Recompiled code"
python3 tools/extract.py "$rom" > /dev/null
inputs="$( (cat us.toml aspMain.us.toml syms/rush2.us.syms.toml rush2.us.recomp.z64 $tools/N64Recomp $tools/RSPRecomp) |
    sha1sum | cut -c1-40)"
if [[ "$(cat $prep/recompiled-stamp 2> /dev/null)" != "$inputs" || ! -f RecompiledFuncs/funcs.h || ! -f rsp/aspMain.cpp ]]; then
    rm -rf RecompiledFuncs
    $tools/N64Recomp us.toml > $prep/n64recomp.log 2>&1 || { tail -20 $prep/n64recomp.log; exit 1; }
    $tools/RSPRecomp aspMain.us.toml >> $prep/n64recomp.log 2>&1 || { tail -20 $prep/n64recomp.log; exit 1; }
    echo "$inputs" > $prep/recompiled-stamp
fi
[[ $prepare_only == 1 ]] && exit 0

# --- 4. The page ---
step "Page"
embuilder build sdl2-mt freetype-legacysjlj > /dev/null 2>&1
[[ -f build-web/build.ninja ]] || emcmake cmake -S . -B build-web -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DRT64_NAGA_EXECUTABLE="$(command -v naga)" -DPython3_EXECUTABLE="$(command -v python3)" > $prep/configure.log 2>&1 ||
    { tail -30 $prep/configure.log; rm -f build-web/build.ninja; exit 1; }
cmake --build build-web --target Rush2Recompiled -j"$jobs"
ls -l build-web/Rush2Recompiled.{html,js,wasm,data}
