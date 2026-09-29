// Own one host pixel buffer per active image size. Dropping an instance on a
// size change releases its linear memory; repeated renders reuse its buffer.
export class WasmPipeline {
  constructor(module) {
    this.module = module;
    this.instance = null;
    this.bufferLength = 0;
    this.pointer = 0;
  }

  apply(src, width, height, operations) {
    const length = width * height * 4;
    if (!Number.isInteger(width) || !Number.isInteger(height) || width < 1 || height < 1 || src.length !== length) {
      throw new Error("Invalid WASM image dimensions or RGBA buffer length");
    }
    if (!this.instance || this.bufferLength !== length) {
      this.instance = new WebAssembly.Instance(this.module, {});
      this.pointer = this.instance.exports.alloc(length);
      this.bufferLength = length;
    }
    const { memory, process_in_place } = this.instance.exports;
    const pointer = this.pointer;
    new Uint8Array(memory.buffer, pointer, length).set(src);
    for (const { id, amount } of operations) {
      if (process_in_place(pointer, width, height, id, amount) !== pointer) {
        throw new Error("WASM in-place buffer pointer changed");
      }
    }
    // Filters may grow memory. Recreate the view and copy out so a later render
    // cannot mutate an earlier result or a buffer transferred to another thread.
    return new Uint8ClampedArray(new Uint8Array(memory.buffer, pointer, length));
  }
}
