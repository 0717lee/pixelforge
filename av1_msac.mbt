/// Pure MoonBit implementation of the AV1 symbol decoder (MSAC).
///
/// The decoder follows section 8.2 of the AV1 specification.  CDF values use
/// the q15 representation used by the bitstream: an N-symbol CDF has N+1
/// entries, with the final entry holding the adaptation counter.
///
/// This file deliberately has no codec or host dependencies.  It is kept
/// separate from the OBU parser so the tile reader can use the exact same
/// arithmetic for booleans, literals and adaptive symbols.

///|
priv struct Av1SymbolDecoder {
  data : Array[Byte]
  mut bit_pos : Int
  mut symbol_value : Int
  mut symbol_range : Int
  mut symbol_max_bits : Int
  mut allow_update : Bool
}

///|
fn Av1SymbolDecoder::read_bits(
  self : Av1SymbolDecoder,
  count : Int,
) -> Int {
  let mut value = 0
  for _ in 0..<count {
    let byte_pos = self.bit_pos >> 3
    let bit = if byte_pos < self.data.length() {
      (self.data[byte_pos].to_int() >> (7 - (self.bit_pos & 7))) & 1
    } else {
      0
    }
    value = (value << 1) | bit
    self.bit_pos = self.bit_pos + 1
  }
  value
}

///|
fn av1_msac_new(data : Array[Byte], allow_update : Bool) -> Av1SymbolDecoder {
  let n = if data.length() * 8 < 15 { data.length() * 8 } else { 15 }
  let initial = Av1SymbolDecoder::read_bits({
    data,
    bit_pos: 0,
    symbol_value: 0,
    symbol_range: 32768,
    symbol_max_bits: 0,
    allow_update,
  }, n)
  {
    data,
    bit_pos: n,
    symbol_value: 32767 ^ (initial << (15 - n)),
    symbol_range: 32768,
    symbol_max_bits: data.length() * 8 - 15,
    allow_update,
  }
}

/// Decode one symbol from a fresh tile state.  This small probe is also useful
/// for conformance tests; full tile decoding keeps the decoder instance alive
/// and calls `symbol` repeatedly.
pub fn av1_msac_decode_first(data : Array[Byte], cdf : Array[Int]) -> Int? {
  if data.length() == 0 || cdf.length() < 2 {
    return None
  }
  let decoder = av1_msac_new(data, false)
  Some(decoder.symbol(cdf))
}

///|
fn av1_msac_floor_log2(value : Int) -> Int {
  let mut x = value
  let mut out = -1
  while x > 0 {
    out = out + 1
    x = x >> 1
  }
  out
}

///|
fn Av1SymbolDecoder::renorm(self : Av1SymbolDecoder) -> Unit {
  let shift = 15 - av1_msac_floor_log2(self.symbol_range)
  self.symbol_range = self.symbol_range << shift
  let mut count = shift
  if self.symbol_max_bits < count {
    count = if self.symbol_max_bits < 0 { 0 } else { self.symbol_max_bits }
  }
  let fresh = self.read_bits(count)
  let padded = fresh << (shift - count)
  self.symbol_value = padded ^ (((self.symbol_value + 1) << shift) - 1)
  self.symbol_max_bits = self.symbol_max_bits - shift
}

/// Adapt one CDF after an adaptive symbol.  The last entry is the update
/// counter and is intentionally not part of the cumulative probabilities.
fn av1_msac_update_cdf(cdf : Array[Int], symbol : Int, n : Int) -> Unit {
  let mut rate = 3
  if cdf[n] > 15 {
    rate = rate + 1
  }
  if cdf[n] > 31 {
    rate = rate + 1
  }
  let logn = av1_msac_floor_log2(n)
  rate = rate + (if logn < 2 { logn } else { 2 })
  let mut target = 0
  for i in 0..<(n - 1) {
    if i == symbol {
      target = 32768
    }
    if target < cdf[i] {
      cdf[i] = cdf[i] - ((cdf[i] - target) >> rate)
    } else {
      cdf[i] = cdf[i] + ((target - cdf[i]) >> rate)
    }
  }
  if cdf[n] < 32 {
    cdf[n] = cdf[n] + 1
  }
}

/// Decode a symbol from an AV1 q15 CDF.  The caller owns the mutable CDF and
/// may reuse it for subsequent symbols in the same tile.
fn Av1SymbolDecoder::symbol(self : Av1SymbolDecoder, cdf : Array[Int]) -> Int {
  let n = cdf.length() - 1
  if n <= 0 {
    return 0
  }
  let mut cur = self.symbol_range
  let mut prev = cur
  let mut symbol = -1
  while symbol + 1 < n {
    symbol = symbol + 1
    prev = cur
    let f = 32768 - cdf[symbol]
    cur = ((self.symbol_range >> 8) * (f >> 6)) >> 1
    cur = cur + 4 * (n - symbol - 1)
    if self.symbol_value >= cur {
      break
    }
  }
  self.symbol_range = prev - cur
  self.symbol_value = self.symbol_value - cur
  self.renorm()
  if self.allow_update {
    av1_msac_update_cdf(cdf, symbol, n)
  }
  symbol
}

/// Decode an equiprobable boolean (the `read_bool` syntax element).
fn Av1SymbolDecoder::bool(self : Av1SymbolDecoder) -> Int {
  let cdf : Array[Int] = [16384, 32768, 0]
  let old = self.allow_update
  self.allow_update = false
  let out = self.symbol(cdf)
  self.allow_update = old
  out
}

/// Decode an unsigned literal, MSB first.
fn Av1SymbolDecoder::literal(self : Av1SymbolDecoder, count : Int) -> Int {
  let mut out = 0
  for _ in 0..<count {
    out = (out << 1) | self.bool()
  }
  out
}

/// Decode the non-symmetric `ns(n)` syntax element.
fn Av1SymbolDecoder::ns(self : Av1SymbolDecoder, n : Int) -> Int {
  if n <= 1 {
    return 0
  }
  let mut w = 0
  while (1 << (w + 1)) <= n {
    w = w + 1
  }
  w = w + 1
  let m = (1 << w) - n
  let v = self.literal(w - 1)
  if v < m {
    v
  } else {
    (v << 1) - m + self.bool()
  }
}

///|
test "av1 msac keeps tile state across symbols" {
  let decoder = av1_msac_new(
    [b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00'],
    false,
  )
  let cdf : Array[Int] = [16384, 32768, 0]
  assert_eq(decoder.symbol(cdf), 0)
  assert_eq(decoder.symbol(cdf), 0)
}
