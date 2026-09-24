#!/usr/bin/env node
// Check browser API routing and resource ownership with mock native decoders.
import assert from "node:assert/strict";
import { browserCodecKind, decodeBrowserImage, decodeWebP, decodeAVIF } from "../web/codecs.js";

const nativeHooks = [
  [globalThis, "createImageBitmap"],
  [globalThis, "Image"],
  [URL, "createObjectURL"],
  [URL, "revokeObjectURL"],
].map(([host, name]) => ({ host, name, descriptor: Object.getOwnPropertyDescriptor(host, name) }));

function setHook(host, name, value) {
  Object.defineProperty(host, name, { configurable: true, writable: true, value });
}

function checkImage(image, kind, source, width, height) {
  assert.deepEqual(Object.keys(image).sort(), ["close", "height", "kind", "mime", "source", "width"]);
  assert.equal(image.kind, kind);
  assert.equal(image.mime, `image/${kind}`);
  assert.equal(image.source, source);
  assert.equal(image.width, width);
  assert.equal(image.height, height);
  assert.equal(typeof image.close, "function");
}

function mockImageHost(blob, width, height, fails = false) {
  const created = [];
  const revoked = [];
  const images = [];
  setHook(globalThis, "createImageBitmap", undefined);
  setHook(URL, "createObjectURL", (input) => {
    assert.equal(input, blob);
    const url = `blob:codec-check/${created.length}`;
    created.push(url);
    return url;
  });
  setHook(URL, "revokeObjectURL", (url) => revoked.push(url));
  setHook(globalThis, "Image", class {
    constructor() {
      this.naturalWidth = width;
      this.naturalHeight = height;
      this.width = 1;
      this.height = 1;
      images.push(this);
    }
    set src(url) {
      this.loadedURL = url;
      queueMicrotask(() => fails ? this.onerror() : this.onload());
    }
  });
  return { created, revoked, images };
}

try {
  for (const [kind, decode] of [["webp", decodeWebP], ["avif", decodeAVIF]]) {
    const mime = `image/${kind}`;
    const blob = new Blob([Uint8Array.of(0)], { type: mime });
    const otherKind = kind === "webp" ? "avif" : "webp";
    assert.equal(browserCodecKind({ type: mime }), kind);
    assert.equal(browserCodecKind({ type: mime.toUpperCase() }), kind);
    assert.equal(browserCodecKind({ name: `picture.${kind}` }), kind);
    assert.equal(browserCodecKind({ name: `PICTURE.${kind.toUpperCase()}` }), kind);
    assert.equal(browserCodecKind({ name: `picture.${kind}.png` }), null);

    let bitmapCalls = 0;
    let imageCalls = 0;
    let urlCalls = 0;
    let closed = 0;
    const bitmap = { width: 7, height: 3, close() { closed++; } };
    setHook(globalThis, "createImageBitmap", async (input) => {
      bitmapCalls++;
      assert.equal(input, blob);
      return bitmap;
    });
    setHook(globalThis, "Image", function () { imageCalls++; throw new Error("unexpected Image fallback"); });
    setHook(URL, "createObjectURL", () => { urlCalls++; throw new Error("unexpected object URL"); });

    // Reject declared MIME conflicts before invoking either host decoder.
    await assert.rejects(decode(new Blob([], { type: "image/png" })), new RegExp(`expected image/${kind}`));
    await assert.rejects(decode(new Blob([], { type: `image/${otherKind}` })), new RegExp(`expected image/${kind}`));
    const conflict = new Blob([], { type: "image/png" });
    Object.defineProperty(conflict, "name", { value: `picture.${kind}` });
    await assert.rejects(decodeBrowserImage(conflict), new RegExp(`expected image/${kind}`));
    assert.equal(bitmapCalls, 0);

    for (const decodeInput of [decode, decodeBrowserImage]) {
      const image = await decodeInput(blob);
      checkImage(image, kind, bitmap, 7, 3);
      assert.equal(closed, bitmapCalls - 1, "bitmap stays open until close()");
      image.close();
      assert.equal(closed, bitmapCalls);
    }
    const namedBlob = new Blob([Uint8Array.of(0)]);
    Object.defineProperty(namedBlob, "name", { value: `picture.${kind}` });
    setHook(globalThis, "createImageBitmap", async (input) => {
      assert.equal(input, namedBlob);
      return bitmap;
    });
    const namedImage = await decodeBrowserImage(namedBlob);
    checkImage(namedImage, kind, bitmap, 7, 3);
    namedImage.close();

    for (const [width, height] of [[0, 3], [7, 0]]) {
      let emptyClosed = 0;
      setHook(globalThis, "createImageBitmap", async () => ({ width, height, close() { emptyClosed++; } }));
      await assert.rejects(decode(blob), /decoder returned an empty image/);
      assert.equal(emptyClosed, 1, "empty bitmap is released");
    }
    const failure = new Error(`${kind} host decode failure`);
    setHook(globalThis, "createImageBitmap", async () => { throw failure; });
    await assert.rejects(decode(blob), (error) => error === failure);
    assert.equal(imageCalls, 0, "bitmap failure must not invoke Image");
    assert.equal(urlCalls, 0, "bitmap path must not create object URLs");

    const success = mockImageHost(blob, 7, 3);
    const image = await decode(blob);
    assert.equal(success.images.length, 1);
    checkImage(image, kind, success.images[0], 7, 3);
    assert.deepEqual(success.created, ["blob:codec-check/0"]);
    assert.equal(success.images[0].loadedURL, success.created[0]);
    assert.deepEqual(success.revoked, [], "object URL stays alive until close()");
    image.close();
    assert.deepEqual(success.revoked, success.created);

    for (const [width, height] of [[0, 3], [7, 0]]) {
      const empty = mockImageHost(blob, width, height);
      await assert.rejects(decode(blob), /decoder returned an empty image/);
      assert.equal(empty.created.length, 1);
      assert.deepEqual(empty.revoked, empty.created, "empty Image releases its object URL");
    }
    const rejected = mockImageHost(blob, 7, 3, true);
    await assert.rejects(decode(blob), /decoder rejected the image/);
    assert.equal(rejected.created.length, 1);
    assert.deepEqual(rejected.revoked, rejected.created, "failed Image releases its object URL");

    setHook(globalThis, "Image", undefined);
    await assert.rejects(decode(blob), /decoding is unavailable in this browser/);
    assert.equal(rejected.created.length, 1, "unavailable decoder must not create a URL");
    setHook(globalThis, "Image", function () { throw new Error("unexpected Image construction"); });
    setHook(URL, "createObjectURL", undefined);
    await assert.rejects(decode(blob), /decoding is unavailable in this browser/);
  }

  for (const value of [null, undefined, {}, { type: "image/png", name: "picture.png" }]) {
    assert.equal(browserCodecKind(value), null);
  }
  await assert.rejects(decodeBrowserImage(null), /expects a Blob/);
  await assert.rejects(decodeBrowserImage(new Blob([], { type: "image/png" })), /only accepts WebP or AVIF/);
  await assert.rejects(decodeBrowserImage(new Blob(), "png"), /only accepts WebP or AVIF/);
  console.log("OK browser WebP/AVIF: MIME and extension routing, declaration conflicts, bitmap ownership and rejection, Image URL lifecycle, unavailable decoder errors");
} finally {
  for (const { host, name, descriptor } of nativeHooks) {
    if (descriptor) Object.defineProperty(host, name, descriptor);
    else delete host[name];
  }
}
