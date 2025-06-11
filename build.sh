#!/usr/bin/env bash
set -euo pipefail

# Chemin vers le fichier source et nom du binaire final
SRC="src/AudioPassThrough.swift"
UNIVERSAL_BIN="AudioPassThroughUniversal"
DEPLOYMENT_TARGET="macosx12.0"
ARCHS=("x86_64" "arm64")

# Parameters for aggregate-device creation tool
AGG_SRC="src/create-agg.swift"
AGG_BIN="create-agg"

# Nettoyer d’anciens binaires intermédiaires si présents
for ARCH in "${ARCHS[@]}"; do
    BIN_NAME="${UNIVERSAL_BIN}_${ARCH}"
    if [ -f "${BIN_NAME}" ]; then
        echo "🧹 Suppression de ${BIN_NAME}"
        rm "${BIN_NAME}"
    fi
    AGG_NAME="${AGG_BIN}_${ARCH}"
    if [ -f "${AGG_NAME}" ]; then
        echo "🧹 Suppression de ${AGG_NAME}"
        rm "${AGG_NAME}"
    fi
done

# Compilation pour chaque architecture
for ARCH in "${ARCHS[@]}"; do
    BIN_NAME="${UNIVERSAL_BIN}_${ARCH}"
    echo "⏳ Compilation pour ${ARCH}..."
    swiftc -target "${ARCH}-apple-${DEPLOYMENT_TARGET}" "${SRC}" -o "${BIN_NAME}"
done

# Compilation de create-agg pour chaque architecture
for ARCH in "${ARCHS[@]}"; do
    AGG_NAME="${AGG_BIN}_${ARCH}"
    echo "⏳ Compilation de ${AGG_BIN} pour ${ARCH}..."
    swiftc -target "${ARCH}-apple-${DEPLOYMENT_TARGET}" -framework CoreAudio "${AGG_SRC}" -o "${AGG_NAME}"
done

# Création du binaire universel
echo "🔗 Assemblage du binaire universel..."
FILES=()
for ARCH in "${ARCHS[@]}"; do
    FILES+=("${UNIVERSAL_BIN}_${ARCH}")
done
lipo -create "${FILES[@]}" -output "${UNIVERSAL_BIN}"

# Création du binaire universel create-agg
echo "🔗 Assemblage du binaire universel ${AGG_BIN}..."
AGG_FILES=()
for ARCH in "${ARCHS[@]}"; do
    AGG_FILES+=("${AGG_BIN}_${ARCH}")
done
lipo -create "${AGG_FILES[@]}" -output "${AGG_BIN}"

# Nettoyage des binaires intermédiaires
echo "🧹 Nettoyage des binaires intermédiaires..."
for ARCH in "${ARCHS[@]}"; do
    rm "${UNIVERSAL_BIN}_${ARCH}"
done

# Nettoyage des binaires intermédiaires create-agg
for ARCH in "${ARCHS[@]}"; do
    rm "${AGG_BIN}_${ARCH}"
done

echo "✅ Terminé : ${UNIVERSAL_BIN}"
echo "✅ Terminé : ${AGG_BIN}"