// Browser-native image codec adapters.
//
// WebP and AVIF decoding is deliberately kept in the browser layer.  The
// MoonBit core remains portable and does not advertise these adapters on the
// native or wasm targets.  The returned source is suitable for drawImage and
// represents the first frame when the browser decoder receives an animation.

const CODEC_MIME = Object.freeze({ webp: "image/webp", avif: "image/avif" });

/** Return the browser codec handled by a File/Blob-like value, or null. */
export function browserCodecKind(value) {
  const type = String(value?.type || "").toLowerCase();
  const name = String(value?.name || "").toLowerCase();
  if (type === CODEC_MIME.webp || /\.webp$/.test(name)) return "webp";
  if (type === CODEC_MIME.avif || /\.avif$/.test(name)) return "avif";
  return null;
}

/**
 * Decode a WebP or AVIF Blob with the host browser's native decoder.
 *
 * The result owns a short-lived ImageBitmap/Image object.  Call `close()`
 * after drawing it; this also releases the object URL used by the fallback
 * decoder.  A browser that cannot decode the requested format rejects the
 * promise instead of silently returning a different image.
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

  // Safari versions without createImageBitmap still expose the HTML image
  // decoder for WebP/AVIF.  Keep the object URL alive until the caller draws.
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

