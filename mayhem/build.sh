#!/usr/bin/env bash
#
# mayhem/build.sh — builds vg's bundled dependencies, a normal vg binary for mayhem/test.sh, a sanitized
# copy of libvg, and one libFuzzer + one standalone binary per harness. Offline and re-runnable: all
# dependencies are git submodules under deps/ (checked out with the repo) plus apt -dev packages.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

: "${SRC:=/mayhem}"
cd "$SRC"

COV_FLAGS="-fsanitize=fuzzer-no-link"

# 1) vg's dependencies (shared by both builds, unsanitized, DWARF 3) and the normal vg binary for test.sh.
#    lld: vcflib is built with clang IPO, whose bitcode archives GNU ld cannot read.
#    libvg.a is removed first: step 2 leaves the sanitized archive there, and bin/vg must be relinked
#    from the normal objects on a re-run.
rm -f lib/libvg.a bin/vg
CXXFLAGS="-gdwarf-3 $COVERAGE_FLAGS" CFLAGS="-gdwarf-3 $COVERAGE_FLAGS" LDFLAGS="-fuse-ld=lld $COVERAGE_FLAGS" \
    make -j"$MAYHEM_JOBS" bin/vg
mkdir -p build-tests
cp bin/vg build-tests/vg

# 2) the vg library itself, sanitized and SanCov-instrumented, into its own object tree (obj-san/).
rm -f lib/libvg.a
CXXFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS $COV_FLAGS" CFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS $COV_FLAGS" LDFLAGS="-fuse-ld=lld" \
    make -j"$MAYHEM_JOBS" OBJ_DIR=obj-san SHARED_OBJ_DIR=obj-san/pic lib/libvg.a
mkdir -p build-fuzz
cp lib/libvg.a build-fuzz/libvg-san.a
rm -f lib/libvg.a

# 3) harnesses.
INCLUDES="-I$SRC/include -I$SRC/include/GFAz -I$SRC -I$SRC/src -I$SRC/include/dynamic -I$SRC/include/cairo"
CXXOPTS="-std=c++20 -O1 -fopenmp -msse4.2 $INCLUDES"
LIBS="-L$SRC/lib -fuse-ld=lld -fopenmp "-Wl,-rpath,$SRC/lib" -Wl,--start-group build-fuzz/libvg-san.a \
 -lvcflib -lwfa2 -ltabixpp -lgssw -lssw -lsublinearLS -lpthread -lncurses -lgcsa2 -lgbwtgraph -lgbwt -lkff \
 -ldivsufsort -ldivsufsort64 -lraptor2 -lpinchesandcacti -l3edgeconnected -lsonlib -lstructures -lbdsg -lxg \
 -lsdsl -lhandlegraph -lgfaz_compress -lgfaz_core -lzstd -pthread -lcrypto -lz -ldl -rdynamic \
 -ldwfl -ldwfl_stacktrace -ldw -ldwelf -lelf -lebl -leu -latomic -lboost_program_options -llzma -lbz2 \
 -Wl,-Bstatic -lvgio -lhts -ldeflate -lz -lbz2 -llzma -lprotobuf -ljansson -Wl,-Bdynamic -lpthread -lm \
 -lcairo -lfontconfig -lfreetype -lpng16 -lbrotlidec -lbrotlicommon -lexpat -lpixman-1 \
 -Wl,--end-group"

$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o build-fuzz/lsan_off.o
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o build-fuzz/standalone_main.o

for h in fuzz_gfa fuzz_snarl_distance fuzz_json_alignment; do
    $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $COV_FLAGS $CXXOPTS -c "mayhem/$h.cpp" -o "build-fuzz/$h.o"
    $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "build-fuzz/$h.o" build-fuzz/lsan_off.o $LIBS -o "$SRC/$h"
    $CXX $SANITIZER_FLAGS $DEBUG_FLAGS "build-fuzz/$h.o" build-fuzz/lsan_off.o build-fuzz/standalone_main.o $LIBS -o "$SRC/$h-standalone"
done
