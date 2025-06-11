#!/usr/bin/env bash
set -euo pipefail

# Chemin vers le fichier source et nom du binaire final
DEPLOYMENT_TARGET="macosx12.0"
ARCHS=("x86_64" "arm64")

# Programs to build
PROGRAM_NAMES=("AudioPassThroughUniversal" "create-agg" "create-multi")
PROGRAM_SRCS=("src/AudioPassThrough.swift" "src/create-agg.swift" "src/create_multi.swift")
PROGRAM_FRAMEWORKS=("" "-framework CoreAudio" "-framework CoreAudio")

# Nettoyer d’anciens binaires intermédiaires si présents
for ARCH in "${ARCHS[@]}"; do
    for prog in "${PROGRAM_NAMES[@]}"; do
        BIN_NAME="${prog}_${ARCH}"
        if [ -f "${BIN_NAME}" ]; then
            echo "🧹 Suppression de ${BIN_NAME}"
            rm "${BIN_NAME}"
        fi
    done
done

# Compile each program for each architecture
for idx in "${!PROGRAM_NAMES[@]}"; do
    prog="${PROGRAM_NAMES[$idx]}"
    src="${PROGRAM_SRCS[$idx]}"
    flags="${PROGRAM_FRAMEWORKS[$idx]}"
    for ARCH in "${ARCHS[@]}"; do
        bin_arch="${prog}_${ARCH}"
        echo "⏳ Compilation de ${prog} pour ${ARCH}..."
        swiftc -target "${ARCH}-apple-${DEPLOYMENT_TARGET}" ${flags} "${src}" -o "${bin_arch}"
    done

    # Build universal binary
    echo "🔗 Assemblage du binaire universel ${prog}..."
    bins=()
    for ARCH in "${ARCHS[@]}"; do
        bins+=("${prog}_${ARCH}")
    done
    lipo -create "${bins[@]}" -output "${prog}"

    # Cleanup
    echo "🧹 Nettoyage des binaires intermédiaires pour ${prog}..."
    for ARCH in "${ARCHS[@]}"; do
        rm "${prog}_${ARCH}"
    done
    echo "✅ Terminé : ${prog}"
done