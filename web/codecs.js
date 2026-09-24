// WebP and AVIF use the host browser's native image decoders.

const CODEC_MIME = Object.freeze({ webp: "image/webp", avif: "image/avif" });

/** Return the codec handled by a File/Blob-like value, or null. */
export function browserCodecKind(value) {
  const type = String(value?.type || "").toLowerCase();
  const name = String(value?.name || "").toLowerCase();
  if (type === CODEC_MIME.webp || /\.webp$/.test(name)) return "webp";
  if (type === CODEC_MIME.avif || /\.avif$/.test(name)) return "avif";
  return null;
}

/**
 * Decode WebP or AVIF with the browser's native image decoder.
 *
 * Returns a short-lived ImageBitmap/Image; call `close()` after drawing it
 * to release its resources. The playground edits one frame; decoding an
 * animation into a frame sequence is outside this adapter's contract.
 */
export async function decodeBrowserImage(blob, expectedKind = null) {
  if (!blob || typeof blob !== "object") throw new TypeError("decodeBrowserImage expects a Blob");
  const kind = expectedKind || browserCodecKind(blob);
  if (kind !== "webp" && kind !== "avif") {
    throw new TypeError("decodeBrowserImage only accepts WebP or AVIF");
  }
  const mime = CODEC_MIME[kind];
  const declared = String(blob.type || "").toLowerCase();
  if (declared && declared !== mime) {
    throw new TypeError(`expected ${mime}, received ${declared}`);
  }
  if (typeof globalThis.createImageBitmap === "function") {
    const bitmap = await globalThis.createImageBitmap(blob);
    if (!bitmap.width || !bitmap.height) {
      bitmap.close?.();
      throw new Error(`${kind.toUpperCase()} decoder returned an empty image`);
    }
    return {
      kind,
      mime,
      source: bitmap,
      width: bitmap.width,
      height: bitmap.height,
      close: () => bitmap.close?.(),
    };
  }

  // Browsers without createImageBitmap may still expose an HTML image
  // decoder. Keep the object URL alive until the caller draws.
  if (typeof globalThis.Image !== "function" || typeof globalThis.URL?.createObjectURL !== "function") {
    throw new Error(`${kind.toUpperCase()} decoding is unavailable in this browser`);
  }
  const url = globalThis.URL.createObjectURL(blob);
  try {
    const image = await new Promise((resolve, reject) => {
      const element = new globalThis.Image();
      element.onload = () => resolve(element);
      element.onerror = () => reject(new Error(`${kind.toUpperCase()} decoder rejected the image`));
      element.src = url;
    });
    if (!image.naturalWidth || !image.naturalHeight) throw new Error(`${kind.toUpperCase()} decoder returned an empty image`);
    return {
      kind,
      mime,
      source: image,
      width: image.naturalWidth,
      height: image.naturalHeight,
      close: () => globalThis.URL.revokeObjectURL(url),
    };
  } catch (error) {
    globalThis.URL.revokeObjectURL(url);
    throw error;
  }
}

export const decodeWebP = (blob) => decodeBrowserImage(blob, "webp");
export const decodeAVIF = (blob) => decodeBrowserImage(blob, "avif");
