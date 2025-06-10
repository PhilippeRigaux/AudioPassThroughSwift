#!/usr/bin/env bash
set -euo pipefail

# Chemin vers le fichier source et nom du binaire final
SRC="src/AudioPassThrough.swift"
UNIVERSAL_BIN="AudioPassThroughUniversal"
DEPLOYMENT_TARGET="macosx12.0"
ARCHS=("x86_64" "arm64")

# Nettoyer d’anciens binaires intermédiaires si présents
for ARCH in "${ARCHS[@]}"; do
    BIN_NAME="${UNIVERSAL_BIN}_${ARCH}"
    if [ -f "${BIN_NAME}" ]; then
        echo "🧹 Suppression de ${BIN_NAME}"
        rm "${BIN_NAME}"
    fi
done

# Compilation pour chaque architecture
for ARCH in "${ARCHS[@]}"; do
    BIN_NAME="${UNIVERSAL_BIN}_${ARCH}"
    echo "⏳ Compilation pour ${ARCH}..."
    swiftc -target "${ARCH}-apple-${DEPLOYMENT_TARGET}" "${SRC}" -o "${BIN_NAME}"
done

# Création du binaire universel
echo "🔗 Assemblage du binaire universel..."
FILES=()
for ARCH in "${ARCHS[@]}"; do
    FILES+=("${UNIVERSAL_BIN}_${ARCH}")
done
lipo -create "${FILES[@]}" -output "${UNIVERSAL_BIN}"

# Nettoyage des binaires intermédiaires
echo "🧹 Nettoyage des binaires intermédiaires..."
for ARCH in "${ARCHS[@]}"; do
    rm "${UNIVERSAL_BIN}_${ARCH}"
done

echo "✅ Terminé : ${UNIVERSAL_BIN}"