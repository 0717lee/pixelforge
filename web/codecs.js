// AVIF uses the shared MoonBit core. WebP keeps its browser-native adapter.
import { decode_avif_rgba, decode_avif_animation } from "./dist/web.js";

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
 * Decode WebP with the browser, or AVIF with the MoonBit core.
 *
 * WebP returns a short-lived ImageBitmap/Image; call `close()` after drawing
 * it to release its resources. AVIF returns owned RGBA frame buffers and
 * integer frame timing without creating any browser image objects.
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
  if (kind === "avif") return decodeAVIF(blob);

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
  // decoder for WebP. Keep the object URL alive until the caller draws.
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

// Routing only: all item/track/extent validation remains in the core parser.
// A declared sequence must not fall back to its still primary on decode error.
function isAvifSequence(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const typeAt = (at) => String.fromCharCode(...bytes.subarray(at, at + 4));
  let sequence = false;
  for (let offset = 0; offset + 8 <= bytes.length;) {
    let size = view.getUint32(offset);
    const type = typeAt(offset + 4);
    let header = 8;
    if (size === 1) {
      if (offset + 16 > bytes.length) throw new Error("AVIF box header is truncated");
      const wide = view.getBigUint64(offset + 8);
      if (wide > BigInt(bytes.length - offset)) throw new Error("AVIF box extent is invalid");
      size = Number(wide);
      header = 16;
    } else if (size === 0) size = bytes.length - offset;
    if (size < header || size > bytes.length - offset) throw new Error("AVIF box extent is invalid");
    if (type === "moov") sequence = true;
    if (type === "ftyp" && size >= header + 8) {
      if (typeAt(offset + header) === "avis") sequence = true;
      for (let at = offset + header + 8; at + 4 <= offset + size; at += 4) {
        if (typeAt(at) === "avis") sequence = true;
      }
    }
    offset += size;
  }
  return sequence;
}

function rgbaFrame(image, timestamp, duration, timescale) {
  if (!image || !Number.isInteger(image.width) || !Number.isInteger(image.height) ||
      image.width < 1 || image.height < 1 || image.width * image.height > 16_000_000 ||
      !(image.data instanceof Uint8Array) || image.data.byteLength !== image.width * image.height * 4) {
    throw new Error("AVIF decoder returned invalid RGBA pixels");
  }
  return { width: image.width, height: image.height,
    data: new Uint8ClampedArray(image.data.buffer, image.data.byteOffset, image.data.byteLength),
    timestamp, duration, timescale };
}

/** Synchronous, DOM-free AVIF adapter shared by the main thread and worker. */
export function decodeAVIFBytes(bytes) {
  if (!(bytes instanceof Uint8Array)) throw new TypeError("AVIF input must be a Uint8Array");
  let frames;
  let timescale = 1;
  if (isAvifSequence(bytes)) {
    const animation = decode_avif_animation(bytes);
    if (!animation || !Number.isInteger(animation.timescale) || animation.timescale <= 0 || !animation.frames?.length) {
      throw new Error("AVIF animation is invalid or unsupported");
    }
    timescale = animation.timescale;
    frames = animation.frames.map((frame) => {
      if (!Number.isInteger(frame.timestamp) || frame.timestamp < 0 || !Number.isInteger(frame.duration) || frame.duration <= 0) {
        throw new Error("AVIF animation has invalid frame timing");
      }
      return rgbaFrame(frame.image, frame.timestamp, frame.duration, timescale);
    });
  } else {
    const image = decode_avif_rgba(bytes);
    if (!image) throw new Error("AVIF image is invalid or unsupported");
    frames = [rgbaFrame(image, 0, 0, 1)];
  }
  return { kind: "avif", mime: CODEC_MIME.avif, width: frames[0].width, height: frames[0].height,
    frames, timescale, animated: frames.length > 1 };
}

export async function decodeAVIF(blob) {
  if (!blob || typeof blob.arrayBuffer !== "function") throw new TypeError("decodeAVIF expects a Blob");
  const declared = String(blob.type || "").toLowerCase();
  if (declared && declared !== CODEC_MIME.avif) throw new TypeError(`expected ${CODEC_MIME.avif}, received ${declared}`);
  return decodeAVIFBytes(new Uint8Array(await blob.arrayBuffer()));
}
