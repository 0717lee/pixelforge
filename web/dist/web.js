class $PanicError extends Error {}
function $panic() {
  throw new $PanicError();
}
const _M0MPB7JSArray4push = (arr, val) => { arr.push(val); };
const _M0MPB7JSArray4copy = (arr) => arr.slice(0);
const _M0MPB7JSArray3pop = (arr) => arr.pop();
function _M0TP270717lee10pixelforge5Image(param0, param1, param2) {
  this.width = param0;
  this.height = param1;
  this.data = param2;
}
function $makebytes(a, b) {
  const arr = new Uint8Array(a);
  if (b !== 0) {
    arr.fill(b);
  }
  return arr;
}
function $bound_check(arr, index) {
  if (index < 0 || index >= arr.length) throw new Error("Index out of bounds");
}
function $make_array_len_and_init(a, b) {
  const arr = new Array(a);
  arr.fill(b);
  return arr;
}
function _M0TP270717lee10pixelforge6Kernel(param0, param1, param2, param3) {
  this.size = param0;
  this.weights = param1;
  this.divisor = param2;
  this.bias = param3;
}
function _M0FPC15abort5abortGuE(msg) {
  $panic();
}
function _M0MPC15array5Array4pushGyE(self, value) {
  _M0MPB7JSArray4push(self, value);
}
function _M0MPC15array5Array4pushGiE(self, value) {
  _M0MPB7JSArray4push(self, value);
}
function _M0MPC15array10FixedArray4copyGyE(self) {
  return _M0MPB7JSArray4copy(self);
}
function _M0MPC16double6Double7to__int(self) {
  return self !== self ? 0 : self >= 2147483647 ? 2147483647 : self <= -2147483648 ? -2147483648 : self | 0;
}
function _M0MPC15array5Array11unsafe__popGiE(self) {
  return _M0MPB7JSArray3pop(self);
}
function _M0MPC15array5Array2atGyE(self, index) {
  const len = self.length;
  return index >= 0 && index < len ? self[index] : $panic();
}
function _M0MPC15array5Array2atGiE(self, index) {
  const len = self.length;
  return index >= 0 && index < len ? self[index] : $panic();
}
function _M0MPC15array5Array2atGdE(self, index) {
  const len = self.length;
  return index >= 0 && index < len ? self[index] : $panic();
}
function _M0MPC15array5Array3setGiE(self, index, value) {
  const len = self.length;
  if (index >= 0 && index < len) {
    self[index] = value;
    return;
  } else {
    $panic();
    return;
  }
}
function _M0MPC15array5Array4makeGiE(len, elem) {
  const arr = new Array(len);
  let _tmp = 0;
  while (true) {
    const i = _tmp;
    if (i < len) {
      arr[i] = elem;
      _tmp = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return arr;
}
function _M0FPC14math3pow(_tmp, _tmp$2) {
  return Math.pow(_tmp, _tmp$2);
}
function _M0MP270717lee10pixelforge5Image4copy(self) {
  return new _M0TP270717lee10pixelforge5Image(self.width, self.height, _M0MPC15array10FixedArray4copyGyE(self.data));
}
function _M0MP270717lee10pixelforge5Image3new(width, height) {
  return new _M0TP270717lee10pixelforge5Image(width, height, $makebytes(Math.imul(Math.imul(width, height) | 0, 4) | 0, 0));
}
function _M0MP270717lee10pixelforge5Image16flip__horizontal(self) {
  const out = _M0MP270717lee10pixelforge5Image3new(self.width, self.height);
  const _bind = self.height;
  let _tmp = 0;
  while (true) {
    const y = _tmp;
    if (y < _bind) {
      const _bind$2 = self.width;
      let _tmp$2 = 0;
      while (true) {
        const x = _tmp$2;
        if (x < _bind$2) {
          const src = Math.imul((Math.imul(y, self.width) | 0) + ((self.width - 1 | 0) - x | 0) | 0, 4) | 0;
          const dst = Math.imul((Math.imul(y, self.width) | 0) + x | 0, 4) | 0;
          const _tmp$3 = out.data;
          const _tmp$4 = self.data;
          $bound_check(_tmp$4, src);
          $bound_check(_tmp$3, dst);
          _tmp$3[dst] = _tmp$4[src];
          const _tmp$5 = out.data;
          const _tmp$6 = dst + 1 | 0;
          const _tmp$7 = self.data;
          const _tmp$8 = src + 1 | 0;
          $bound_check(_tmp$7, _tmp$8);
          $bound_check(_tmp$5, _tmp$6);
          _tmp$5[_tmp$6] = _tmp$7[_tmp$8];
          const _tmp$9 = out.data;
          const _tmp$10 = dst + 2 | 0;
          const _tmp$11 = self.data;
          const _tmp$12 = src + 2 | 0;
          $bound_check(_tmp$11, _tmp$12);
          $bound_check(_tmp$9, _tmp$10);
          _tmp$9[_tmp$10] = _tmp$11[_tmp$12];
          const _tmp$13 = out.data;
          const _tmp$14 = dst + 3 | 0;
          const _tmp$15 = self.data;
          const _tmp$16 = src + 3 | 0;
          $bound_check(_tmp$15, _tmp$16);
          $bound_check(_tmp$13, _tmp$14);
          _tmp$13[_tmp$14] = _tmp$15[_tmp$16];
          _tmp$2 = x + 1 | 0;
          continue;
        } else {
          break;
        }
      }
      _tmp = y + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return out;
}
function _M0MP270717lee10pixelforge5Image14flip__vertical(self) {
  const out = _M0MP270717lee10pixelforge5Image3new(self.width, self.height);
  const _bind = self.height;
  let _tmp = 0;
  while (true) {
    const y = _tmp;
    if (y < _bind) {
      const _bind$2 = self.width;
      let _tmp$2 = 0;
      while (true) {
        const x = _tmp$2;
        if (x < _bind$2) {
          const src = Math.imul((Math.imul((self.height - 1 | 0) - y | 0, self.width) | 0) + x | 0, 4) | 0;
          const dst = Math.imul((Math.imul(y, self.width) | 0) + x | 0, 4) | 0;
          const _tmp$3 = out.data;
          const _tmp$4 = self.data;
          $bound_check(_tmp$4, src);
          $bound_check(_tmp$3, dst);
          _tmp$3[dst] = _tmp$4[src];
          const _tmp$5 = out.data;
          const _tmp$6 = dst + 1 | 0;
          const _tmp$7 = self.data;
          const _tmp$8 = src + 1 | 0;
          $bound_check(_tmp$7, _tmp$8);
          $bound_check(_tmp$5, _tmp$6);
          _tmp$5[_tmp$6] = _tmp$7[_tmp$8];
          const _tmp$9 = out.data;
          const _tmp$10 = dst + 2 | 0;
          const _tmp$11 = self.data;
          const _tmp$12 = src + 2 | 0;
          $bound_check(_tmp$11, _tmp$12);
          $bound_check(_tmp$9, _tmp$10);
          _tmp$9[_tmp$10] = _tmp$11[_tmp$12];
          const _tmp$13 = out.data;
          const _tmp$14 = dst + 3 | 0;
          const _tmp$15 = self.data;
          const _tmp$16 = src + 3 | 0;
          $bound_check(_tmp$15, _tmp$16);
          $bound_check(_tmp$13, _tmp$14);
          _tmp$13[_tmp$14] = _tmp$15[_tmp$16];
          _tmp$2 = x + 1 | 0;
          continue;
        } else {
          break;
        }
      }
      _tmp = y + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return out;
}
function _M0FP270717lee10pixelforge8push__u8(buf, v) {
  _M0MPC15array5Array4pushGyE(buf, (((v % 256 | 0) + 256 | 0) % 256 | 0) & 255);
}
function _M0FP270717lee10pixelforge13push__u32__be(buf, v) {
  _M0FP270717lee10pixelforge8push__u8(buf, v / 16777216 | 0);
  _M0FP270717lee10pixelforge8push__u8(buf, v / 65536 | 0);
  _M0FP270717lee10pixelforge8push__u8(buf, v / 256 | 0);
  _M0FP270717lee10pixelforge8push__u8(buf, v);
}
function _M0FP270717lee10pixelforge5crc32(data, from, to) {
  let crc = -1;
  let _tmp = from;
  while (true) {
    const i = _tmp;
    if (i < to) {
      const _tmp$2 = crc;
      const _p = _M0MPC15array5Array2atGyE(data, i);
      crc = _tmp$2 ^ _p;
      let _tmp$3 = 0;
      while (true) {
        const _ = _tmp$3;
        if (_ < 8) {
          if ((crc & 1) !== 0) {
            crc = crc >>> 1 ^ -306674912;
          } else {
            crc = crc >>> 1 | 0;
          }
          _tmp$3 = _ + 1 | 0;
          continue;
        } else {
          break;
        }
      }
      _tmp = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return crc ^ -1;
}
function _M0FP270717lee10pixelforge7adler32(data, from, to) {
  let a = 1;
  let b = 0;
  let _tmp = from;
  while (true) {
    const i = _tmp;
    if (i < to) {
      const _tmp$2 = a;
      const _p = _M0MPC15array5Array2atGyE(data, i);
      a = (((_tmp$2 >>> 0) + (_p >>> 0) | 0) >>> 0) % (65521 >>> 0) | 0;
      b = (((b >>> 0) + (a >>> 0) | 0) >>> 0) % (65521 >>> 0) | 0;
      _tmp = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return b << 16 | a;
}
function _M0FP270717lee10pixelforge14push__uint__be(buf, v) {
  const _p = v >>> 24 & 255;
  _M0MPC15array5Array4pushGyE(buf, _p & 255);
  const _p$2 = v >>> 16 & 255;
  _M0MPC15array5Array4pushGyE(buf, _p$2 & 255);
  const _p$3 = v >>> 8 & 255;
  _M0MPC15array5Array4pushGyE(buf, _p$3 & 255);
  const _p$4 = v & 255;
  _M0MPC15array5Array4pushGyE(buf, _p$4 & 255);
}
function _M0FP270717lee10pixelforge11push__chunk(out, ctype, payload) {
  _M0FP270717lee10pixelforge13push__u32__be(out, payload.length);
  const crc_start = out.length;
  const _bind = ctype.length;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const t = ctype[_];
      _M0FP270717lee10pixelforge8push__u8(out, t);
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const _bind$2 = payload.length;
  let _tmp$2 = 0;
  while (true) {
    const _ = _tmp$2;
    if (_ < _bind$2) {
      const b = payload[_];
      _M0MPC15array5Array4pushGyE(out, b);
      _tmp$2 = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  _M0FP270717lee10pixelforge14push__uint__be(out, _M0FP270717lee10pixelforge5crc32(out, crc_start, out.length));
}
function _M0FP270717lee10pixelforge11png__encode(img) {
  const out = [];
  const _bind = [137, 80, 78, 71, 13, 10, 26, 10];
  const _bind$2 = _bind.length;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind$2) {
      const s = _bind[_];
      _M0FP270717lee10pixelforge8push__u8(out, s);
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const ihdr = [];
  _M0FP270717lee10pixelforge13push__u32__be(ihdr, img.width);
  _M0FP270717lee10pixelforge13push__u32__be(ihdr, img.height);
  const _bind$3 = [8, 6, 0, 0, 0];
  const _bind$4 = _bind$3.length;
  let _tmp$2 = 0;
  while (true) {
    const _ = _tmp$2;
    if (_ < _bind$4) {
      const v = _bind$3[_];
      _M0FP270717lee10pixelforge8push__u8(ihdr, v);
      _tmp$2 = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  _M0FP270717lee10pixelforge11push__chunk(out, [73, 72, 68, 82], ihdr);
  const raw = [];
  const _bind$5 = img.height;
  let _tmp$3 = 0;
  while (true) {
    const y = _tmp$3;
    if (y < _bind$5) {
      _M0MPC15array5Array4pushGyE(raw, 0);
      const _bind$6 = Math.imul(img.width, 4) | 0;
      let _tmp$4 = 0;
      while (true) {
        const x = _tmp$4;
        if (x < _bind$6) {
          const _tmp$5 = img.data;
          const _tmp$6 = (Math.imul(Math.imul(y, img.width) | 0, 4) | 0) + x | 0;
          $bound_check(_tmp$5, _tmp$6);
          _M0MPC15array5Array4pushGyE(raw, _tmp$5[_tmp$6]);
          _tmp$4 = x + 1 | 0;
          continue;
        } else {
          break;
        }
      }
      _tmp$3 = y + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const idat = [];
  _M0MPC15array5Array4pushGyE(idat, 120);
  _M0MPC15array5Array4pushGyE(idat, 1);
  let off = 0;
  while (true) {
    if (off < raw.length || raw.length === 0) {
      const chunk = (raw.length - off | 0) > 65535 ? 65535 : raw.length - off | 0;
      const last = (off + chunk | 0) >= raw.length;
      _M0MPC15array5Array4pushGyE(idat, last ? 1 : 0);
      _M0FP270717lee10pixelforge8push__u8(idat, chunk % 256 | 0);
      _M0FP270717lee10pixelforge8push__u8(idat, chunk / 256 | 0);
      _M0FP270717lee10pixelforge8push__u8(idat, 255 - (chunk % 256 | 0) | 0);
      _M0FP270717lee10pixelforge8push__u8(idat, 255 - (chunk / 256 | 0) | 0);
      let _tmp$4 = 0;
      while (true) {
        const i = _tmp$4;
        if (i < chunk) {
          _M0MPC15array5Array4pushGyE(idat, _M0MPC15array5Array2atGyE(raw, off + i | 0));
          _tmp$4 = i + 1 | 0;
          continue;
        } else {
          break;
        }
      }
      off = off + chunk | 0;
      if (last) {
        break;
      }
      continue;
    } else {
      break;
    }
  }
  _M0FP270717lee10pixelforge14push__uint__be(idat, _M0FP270717lee10pixelforge7adler32(raw, 0, raw.length));
  _M0FP270717lee10pixelforge11push__chunk(out, [73, 68, 65, 84], idat);
  _M0FP270717lee10pixelforge11push__chunk(out, [73, 69, 78, 68], []);
  return out;
}
function _M0MP270717lee10pixelforge5Image15luma__histogram(self) {
  const hist = $make_array_len_and_init(256, 0);
  const n = Math.imul(self.width, self.height) | 0;
  let _tmp = 0;
  while (true) {
    const p = _tmp;
    if (p < n) {
      const base = Math.imul(p, 4) | 0;
      const _tmp$2 = self.data;
      $bound_check(_tmp$2, base);
      const _tmp$3 = Math.imul(299, _tmp$2[base]) | 0;
      const _tmp$4 = self.data;
      const _tmp$5 = base + 1 | 0;
      $bound_check(_tmp$4, _tmp$5);
      const _tmp$6 = _tmp$3 + (Math.imul(587, _tmp$4[_tmp$5]) | 0) | 0;
      const _tmp$7 = self.data;
      const _tmp$8 = base + 2 | 0;
      $bound_check(_tmp$7, _tmp$8);
      const y = (_tmp$6 + (Math.imul(114, _tmp$7[_tmp$8]) | 0) | 0) / 1000 | 0;
      $bound_check(hist, y);
      $bound_check(hist, y);
      hist[y] = hist[y] + 1 | 0;
      _tmp = p + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return hist;
}
function _M0MP270717lee10pixelforge5Image15otsu__threshold(self) {
  const hist = _M0MP270717lee10pixelforge5Image15luma__histogram(self);
  const total = Math.imul(self.width, self.height) | 0;
  if (total === 0) {
    return 0;
  }
  let sum_all = 0;
  let _tmp = 0;
  while (true) {
    const i = _tmp;
    if (i < 256) {
      const _tmp$2 = sum_all;
      $bound_check(hist, i);
      sum_all = _tmp$2 + ((Math.imul(i, hist[i]) | 0) + 0);
      _tmp = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  let w_b = 0;
  let sum_b = 0;
  let best_t = 0;
  let best_var = -1;
  let _tmp$2 = 0;
  while (true) {
    const t = _tmp$2;
    if (t < 256) {
      _L: {
        const _tmp$3 = w_b;
        $bound_check(hist, t);
        w_b = _tmp$3 + hist[t] | 0;
        if (w_b === 0) {
          break _L;
        }
        const w_f = total - w_b | 0;
        if (w_f === 0) {
          break;
        }
        const _tmp$4 = sum_b;
        $bound_check(hist, t);
        sum_b = _tmp$4 + ((Math.imul(t, hist[t]) | 0) + 0);
        const mean_b = sum_b / (w_b + 0);
        const mean_f = (sum_all - sum_b) / (w_f + 0);
        const diff = mean_b - mean_f;
        const between = (w_b + 0) * (w_f + 0) * diff * diff;
        if (between > best_var) {
          best_var = between;
          best_t = t;
        }
        break _L;
      }
      _tmp$2 = t + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return best_t;
}
function _M0MP270717lee10pixelforge5Image8map__rgb(self, transform) {
  const out = _M0MP270717lee10pixelforge5Image4copy(self);
  const n = Math.imul(self.width, self.height) | 0;
  let _tmp = 0;
  while (true) {
    const p = _tmp;
    if (p < n) {
      const base = Math.imul(p, 4) | 0;
      const _tmp$2 = self.data;
      $bound_check(_tmp$2, base);
      const r = _tmp$2[base];
      const _tmp$3 = self.data;
      const _tmp$4 = base + 1 | 0;
      $bound_check(_tmp$3, _tmp$4);
      const g = _tmp$3[_tmp$4];
      const _tmp$5 = self.data;
      const _tmp$6 = base + 2 | 0;
      $bound_check(_tmp$5, _tmp$6);
      const b = _tmp$5[_tmp$6];
      const _bind = transform(r, g, b);
      const _nr = _bind._0;
      const _ng = _bind._1;
      const _nb = _bind._2;
      const _tmp$7 = out.data;
      $bound_check(_tmp$7, base);
      _tmp$7[base] = _nr < 0 ? 0 : _nr > 255 ? 255 : _nr & 255;
      const _tmp$8 = out.data;
      const _tmp$9 = base + 1 | 0;
      $bound_check(_tmp$8, _tmp$9);
      _tmp$8[_tmp$9] = _ng < 0 ? 0 : _ng > 255 ? 255 : _ng & 255;
      const _tmp$10 = out.data;
      const _tmp$11 = base + 2 | 0;
      $bound_check(_tmp$10, _tmp$11);
      _tmp$10[_tmp$11] = _nb < 0 ? 0 : _nb > 255 ? 255 : _nb & 255;
      _tmp = p + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return out;
}
function _M0MP270717lee10pixelforge5Image4otsu(self) {
  const t = _M0MP270717lee10pixelforge5Image15otsu__threshold(self);
  return _M0MP270717lee10pixelforge5Image8map__rgb(self, (r, g, b) => {
    const y = (((Math.imul(299, r) | 0) + (Math.imul(587, g) | 0) | 0) + (Math.imul(114, b) | 0) | 0) / 1000 | 0;
    const v = y > t ? 255 : 0;
    return { _0: v, _1: v, _2: v };
  });
}
function _M0MP270717lee10pixelforge5Image11from__bytes(width, height, data) {
  if (data.length !== (Math.imul(Math.imul(width, height) | 0, 4) | 0)) {
    _M0FPC15abort5abortGuE("Image::from_bytes: buffer length must equal width * height * 4");
  }
  return new _M0TP270717lee10pixelforge5Image(width, height, data);
}
function _M0MP270717lee10pixelforge5Image5gamma(self, value) {
  const g = value <= 0 ? 1 : value;
  const inv = 1 / g;
  const lut = $make_array_len_and_init(256, 0);
  let _tmp = 0;
  while (true) {
    const i = _tmp;
    if (i < 256) {
      const normalized = (i + 0) / 255;
      $bound_check(lut, i);
      lut[i] = _M0MPC16double6Double7to__int(_M0FPC14math3pow(normalized, inv) * 255 + 0.5);
      _tmp = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return _M0MP270717lee10pixelforge5Image8map__rgb(self, (r, g$2, b) => {
    $bound_check(lut, r);
    const _tmp$2 = lut[r];
    $bound_check(lut, g$2);
    const _tmp$3 = lut[g$2];
    $bound_check(lut, b);
    return { _0: _tmp$2, _1: _tmp$3, _2: lut[b] };
  });
}
function _M0MP270717lee10pixelforge5Image8vignette(self, strength) {
  const s = strength < 0 ? 0 : strength > 1 ? 1 : strength;
  const out = _M0MP270717lee10pixelforge5Image4copy(self);
  const cx = ((self.width - 1 | 0) + 0) / 2;
  const cy = ((self.height - 1 | 0) + 0) / 2;
  const max_d2 = cx * cx + cy * cy;
  if (max_d2 <= 0) {
    return out;
  }
  const _bind = self.height;
  let _tmp = 0;
  while (true) {
    const y = _tmp;
    if (y < _bind) {
      const _bind$2 = self.width;
      let _tmp$2 = 0;
      while (true) {
        const x = _tmp$2;
        if (x < _bind$2) {
          const dx = x + 0 - cx;
          const dy = y + 0 - cy;
          const factor = 1 - s * (dx * dx + dy * dy) / max_d2;
          const base = Math.imul((Math.imul(y, self.width) | 0) + x | 0, 4) | 0;
          const _tmp$3 = out.data;
          const _tmp$4 = out.data;
          $bound_check(_tmp$4, base);
          const _p = _M0MPC16double6Double7to__int((_tmp$4[base] + 0) * factor + 0.5);
          $bound_check(_tmp$3, base);
          _tmp$3[base] = _p < 0 ? 0 : _p > 255 ? 255 : _p & 255;
          const _tmp$5 = out.data;
          const _tmp$6 = base + 1 | 0;
          const _tmp$7 = out.data;
          const _tmp$8 = base + 1 | 0;
          $bound_check(_tmp$7, _tmp$8);
          const _p$2 = _M0MPC16double6Double7to__int((_tmp$7[_tmp$8] + 0) * factor + 0.5);
          $bound_check(_tmp$5, _tmp$6);
          _tmp$5[_tmp$6] = _p$2 < 0 ? 0 : _p$2 > 255 ? 255 : _p$2 & 255;
          const _tmp$9 = out.data;
          const _tmp$10 = base + 2 | 0;
          const _tmp$11 = out.data;
          const _tmp$12 = base + 2 | 0;
          $bound_check(_tmp$11, _tmp$12);
          const _p$3 = _M0MPC16double6Double7to__int((_tmp$11[_tmp$12] + 0) * factor + 0.5);
          $bound_check(_tmp$9, _tmp$10);
          _tmp$9[_tmp$10] = _p$3 < 0 ? 0 : _p$3 > 255 ? 255 : _p$3 & 255;
          _tmp$2 = x + 1 | 0;
          continue;
        } else {
          break;
        }
      }
      _tmp = y + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return out;
}
function _M0MP270717lee10pixelforge5Image9grayscale(self) {
  return _M0MP270717lee10pixelforge5Image8map__rgb(self, (r, g, b) => {
    const y = (((Math.imul(299, r) | 0) + (Math.imul(587, g) | 0) | 0) + (Math.imul(114, b) | 0) | 0) / 1000 | 0;
    return { _0: y, _1: y, _2: y };
  });
}
function _M0MP270717lee10pixelforge5Image6invert(self) {
  return _M0MP270717lee10pixelforge5Image8map__rgb(self, (r, g, b) => ({ _0: 255 - r | 0, _1: 255 - g | 0, _2: 255 - b | 0 }));
}
function _M0MP270717lee10pixelforge5Image10brightness(self, delta) {
  return _M0MP270717lee10pixelforge5Image8map__rgb(self, (r, g, b) => ({ _0: r + delta | 0, _1: g + delta | 0, _2: b + delta | 0 }));
}
function _M0MP270717lee10pixelforge5Image8contrastN5applyS561(factor, c) {
  return _M0MPC16double6Double7to__int((c + 0 - 128) * factor + 128);
}
function _M0MP270717lee10pixelforge5Image8contrast(self, factor) {
  return _M0MP270717lee10pixelforge5Image8map__rgb(self, (r, g, b) => ({ _0: _M0MP270717lee10pixelforge5Image8contrastN5applyS561(factor, r), _1: _M0MP270717lee10pixelforge5Image8contrastN5applyS561(factor, g), _2: _M0MP270717lee10pixelforge5Image8contrastN5applyS561(factor, b) }));
}
function _M0MP270717lee10pixelforge5Image5sepia(self) {
  return _M0MP270717lee10pixelforge5Image8map__rgb(self, (r, g, b) => {
    const nr = (((Math.imul(393, r) | 0) + (Math.imul(769, g) | 0) | 0) + (Math.imul(189, b) | 0) | 0) / 1000 | 0;
    const ng = (((Math.imul(349, r) | 0) + (Math.imul(686, g) | 0) | 0) + (Math.imul(168, b) | 0) | 0) / 1000 | 0;
    const nb = (((Math.imul(272, r) | 0) + (Math.imul(534, g) | 0) | 0) + (Math.imul(131, b) | 0) | 0) / 1000 | 0;
    return { _0: nr, _1: ng, _2: nb };
  });
}
function _M0MP270717lee10pixelforge5Image9threshold(self, level) {
  return _M0MP270717lee10pixelforge5Image8map__rgb(self, (r, g, b) => {
    const y = (((Math.imul(299, r) | 0) + (Math.imul(587, g) | 0) | 0) + (Math.imul(114, b) | 0) | 0) / 1000 | 0;
    const v = y >= level ? 255 : 0;
    return { _0: v, _1: v, _2: v };
  });
}
function _M0MP270717lee10pixelforge5Image8pixelate(self, block) {
  const size = block < 1 ? 1 : block;
  const out = _M0MP270717lee10pixelforge5Image3new(self.width, self.height);
  const blocks_y = ((self.height + size | 0) - 1 | 0) / size | 0;
  const blocks_x = ((self.width + size | 0) - 1 | 0) / size | 0;
  let _tmp = 0;
  while (true) {
    const byi = _tmp;
    if (byi < blocks_y) {
      let _tmp$2 = 0;
      while (true) {
        const bxi = _tmp$2;
        if (bxi < blocks_x) {
          const y0 = Math.imul(byi, size) | 0;
          const x0 = Math.imul(bxi, size) | 0;
          const _p = y0 + size | 0;
          const _p$2 = self.height;
          const y1 = _p < _p$2 ? _p : _p$2;
          const _p$3 = x0 + size | 0;
          const _p$4 = self.width;
          const x1 = _p$3 < _p$4 ? _p$3 : _p$4;
          let sr = 0;
          let sg = 0;
          let sb = 0;
          let count = 0;
          let _tmp$3 = y0;
          while (true) {
            const y = _tmp$3;
            if (y < y1) {
              let _tmp$4 = x0;
              while (true) {
                const x = _tmp$4;
                if (x < x1) {
                  const base = Math.imul((Math.imul(y, self.width) | 0) + x | 0, 4) | 0;
                  const _tmp$5 = sr;
                  const _tmp$6 = self.data;
                  $bound_check(_tmp$6, base);
                  sr = _tmp$5 + _tmp$6[base] | 0;
                  const _tmp$7 = sg;
                  const _tmp$8 = self.data;
                  const _tmp$9 = base + 1 | 0;
                  $bound_check(_tmp$8, _tmp$9);
                  sg = _tmp$7 + _tmp$8[_tmp$9] | 0;
                  const _tmp$10 = sb;
                  const _tmp$11 = self.data;
                  const _tmp$12 = base + 2 | 0;
                  $bound_check(_tmp$11, _tmp$12);
                  sb = _tmp$10 + _tmp$11[_tmp$12] | 0;
                  count = count + 1 | 0;
                  _tmp$4 = x + 1 | 0;
                  continue;
                } else {
                  break;
                }
              }
              _tmp$3 = y + 1 | 0;
              continue;
            } else {
              break;
            }
          }
          const _p$5 = sr / count | 0;
          const ar = _p$5 < 0 ? 0 : _p$5 > 255 ? 255 : _p$5 & 255;
          const _p$6 = sg / count | 0;
          const ag = _p$6 < 0 ? 0 : _p$6 > 255 ? 255 : _p$6 & 255;
          const _p$7 = sb / count | 0;
          const ab = _p$7 < 0 ? 0 : _p$7 > 255 ? 255 : _p$7 & 255;
          let _tmp$4 = y0;
          while (true) {
            const y = _tmp$4;
            if (y < y1) {
              let _tmp$5 = x0;
              while (true) {
                const x = _tmp$5;
                if (x < x1) {
                  const base = Math.imul((Math.imul(y, self.width) | 0) + x | 0, 4) | 0;
                  const _tmp$6 = out.data;
                  $bound_check(_tmp$6, base);
                  _tmp$6[base] = ar;
                  const _tmp$7 = out.data;
                  const _tmp$8 = base + 1 | 0;
                  $bound_check(_tmp$7, _tmp$8);
                  _tmp$7[_tmp$8] = ag;
                  const _tmp$9 = out.data;
                  const _tmp$10 = base + 2 | 0;
                  $bound_check(_tmp$9, _tmp$10);
                  _tmp$9[_tmp$10] = ab;
                  const _tmp$11 = out.data;
                  const _tmp$12 = base + 3 | 0;
                  const _tmp$13 = self.data;
                  const _tmp$14 = base + 3 | 0;
                  $bound_check(_tmp$13, _tmp$14);
                  $bound_check(_tmp$11, _tmp$12);
                  _tmp$11[_tmp$12] = _tmp$13[_tmp$14];
                  _tmp$5 = x + 1 | 0;
                  continue;
                } else {
                  break;
                }
              }
              _tmp$4 = y + 1 | 0;
              continue;
            } else {
              break;
            }
          }
          _tmp$2 = bxi + 1 | 0;
          continue;
        } else {
          break;
        }
      }
      _tmp = byi + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return out;
}
function _M0FP270717lee10pixelforge15median__channel(img, x, y, ch) {
  const vals = $make_array_len_and_init(9, 0);
  let k = 0;
  let _tmp = -1;
  while (true) {
    const dy = _tmp;
    if (dy < 2) {
      let _tmp$2 = -1;
      while (true) {
        const dx = _tmp$2;
        if (dx < 2) {
          const _p = x + dx | 0;
          const _p$2 = img.width;
          const sx = _p < 0 ? 0 : _p >= _p$2 ? _p$2 - 1 | 0 : _p;
          const _p$3 = y + dy | 0;
          const _p$4 = img.height;
          const sy = _p$3 < 0 ? 0 : _p$3 >= _p$4 ? _p$4 - 1 | 0 : _p$3;
          const _tmp$3 = k;
          const _tmp$4 = img.data;
          const _tmp$5 = (Math.imul((Math.imul(sy, img.width) | 0) + sx | 0, 4) | 0) + ch | 0;
          $bound_check(_tmp$4, _tmp$5);
          $bound_check(vals, _tmp$3);
          vals[_tmp$3] = _tmp$4[_tmp$5];
          k = k + 1 | 0;
          _tmp$2 = dx + 1 | 0;
          continue;
        } else {
          break;
        }
      }
      _tmp = dy + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  let _tmp$2 = 1;
  while (true) {
    const i = _tmp$2;
    if (i < 9) {
      $bound_check(vals, i);
      const v = vals[i];
      let j = i - 1 | 0;
      while (true) {
        let _tmp$3;
        if (j >= 0) {
          const _tmp$4 = j;
          $bound_check(vals, _tmp$4);
          _tmp$3 = vals[_tmp$4] > v;
        } else {
          _tmp$3 = false;
        }
        if (_tmp$3) {
          const _tmp$4 = j + 1 | 0;
          const _tmp$5 = j;
          $bound_check(vals, _tmp$5);
          $bound_check(vals, _tmp$4);
          vals[_tmp$4] = vals[_tmp$5];
          j = j - 1 | 0;
          continue;
        } else {
          break;
        }
      }
      const _tmp$3 = j + 1 | 0;
      $bound_check(vals, _tmp$3);
      vals[_tmp$3] = v;
      _tmp$2 = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  $bound_check(vals, 4);
  const _p = vals[4];
  return _p < 0 ? 0 : _p > 255 ? 255 : _p & 255;
}
function _M0MP270717lee10pixelforge5Image6median(self) {
  const out = _M0MP270717lee10pixelforge5Image3new(self.width, self.height);
  const _bind = self.height;
  let _tmp = 0;
  while (true) {
    const y = _tmp;
    if (y < _bind) {
      const _bind$2 = self.width;
      let _tmp$2 = 0;
      while (true) {
        const x = _tmp$2;
        if (x < _bind$2) {
          const base = Math.imul((Math.imul(y, self.width) | 0) + x | 0, 4) | 0;
          const _tmp$3 = out.data;
          $bound_check(_tmp$3, base);
          _tmp$3[base] = _M0FP270717lee10pixelforge15median__channel(self, x, y, 0);
          const _tmp$4 = out.data;
          const _tmp$5 = base + 1 | 0;
          $bound_check(_tmp$4, _tmp$5);
          _tmp$4[_tmp$5] = _M0FP270717lee10pixelforge15median__channel(self, x, y, 1);
          const _tmp$6 = out.data;
          const _tmp$7 = base + 2 | 0;
          $bound_check(_tmp$6, _tmp$7);
          _tmp$6[_tmp$7] = _M0FP270717lee10pixelforge15median__channel(self, x, y, 2);
          const _tmp$8 = out.data;
          const _tmp$9 = base + 3 | 0;
          const _tmp$10 = self.data;
          const _tmp$11 = base + 3 | 0;
          $bound_check(_tmp$10, _tmp$11);
          $bound_check(_tmp$8, _tmp$9);
          _tmp$8[_tmp$9] = _tmp$10[_tmp$11];
          _tmp$2 = x + 1 | 0;
          continue;
        } else {
          break;
        }
      }
      _tmp = y + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return out;
}
function _M0MP270717lee10pixelforge5Image19histogram__equalize(self) {
  const n = Math.imul(self.width, self.height) | 0;
  const hist = $make_array_len_and_init(256, 0);
  let _tmp = 0;
  while (true) {
    const p = _tmp;
    if (p < n) {
      const base = Math.imul(p, 4) | 0;
      const _tmp$2 = self.data;
      $bound_check(_tmp$2, base);
      const _tmp$3 = Math.imul(299, _tmp$2[base]) | 0;
      const _tmp$4 = self.data;
      const _tmp$5 = base + 1 | 0;
      $bound_check(_tmp$4, _tmp$5);
      const _tmp$6 = _tmp$3 + (Math.imul(587, _tmp$4[_tmp$5]) | 0) | 0;
      const _tmp$7 = self.data;
      const _tmp$8 = base + 2 | 0;
      $bound_check(_tmp$7, _tmp$8);
      const y = (_tmp$6 + (Math.imul(114, _tmp$7[_tmp$8]) | 0) | 0) / 1000 | 0;
      $bound_check(hist, y);
      $bound_check(hist, y);
      hist[y] = hist[y] + 1 | 0;
      _tmp = p + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const cdf = $make_array_len_and_init(256, 0);
  let acc = 0;
  let _tmp$2 = 0;
  while (true) {
    const i = _tmp$2;
    if (i < 256) {
      const _tmp$3 = acc;
      $bound_check(hist, i);
      acc = _tmp$3 + hist[i] | 0;
      $bound_check(cdf, i);
      cdf[i] = acc;
      _tmp$2 = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  let cdf_min = 0;
  let _tmp$3 = 0;
  while (true) {
    const i = _tmp$3;
    if (i < 256) {
      $bound_check(cdf, i);
      if (cdf[i] !== 0) {
        $bound_check(cdf, i);
        cdf_min = cdf[i];
        break;
      }
      _tmp$3 = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const denom = n - cdf_min | 0;
  const lut = $make_array_len_and_init(256, 0);
  let _tmp$4 = 0;
  while (true) {
    const i = _tmp$4;
    if (i < 256) {
      let _tmp$5;
      if (denom <= 0) {
        _tmp$5 = i;
      } else {
        $bound_check(cdf, i);
        _tmp$5 = (Math.imul(cdf[i] - cdf_min | 0, 255) | 0) / denom | 0;
      }
      $bound_check(lut, i);
      lut[i] = _tmp$5;
      _tmp$4 = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return _M0MP270717lee10pixelforge5Image8map__rgb(self, (r, g, b) => {
    const y = (((Math.imul(299, r) | 0) + (Math.imul(587, g) | 0) | 0) + (Math.imul(114, b) | 0) | 0) / 1000 | 0;
    $bound_check(lut, y);
    const e = lut[y];
    return { _0: e, _1: e, _2: e };
  });
}
function _M0MP270717lee10pixelforge5Image9posterize(self, levels) {
  const l = levels < 2 ? 2 : levels > 256 ? 256 : levels;
  return _M0MP270717lee10pixelforge5Image8map__rgb(self, (r, g, b) => ({ _0: (Math.imul((Math.imul(r, l) | 0) / 256 | 0, 255) | 0) / (l - 1 | 0) | 0, _1: (Math.imul((Math.imul(g, l) | 0) / 256 | 0, 255) | 0) / (l - 1 | 0) | 0, _2: (Math.imul((Math.imul(b, l) | 0) / 256 | 0, 255) | 0) / (l - 1 | 0) | 0 }));
}
function _M0FP270717lee10pixelforge7diffuse(buf, w, h, x, y, err) {
  if ((x + 1 | 0) < w) {
    _M0MPC15array5Array3setGiE(buf, ((Math.imul(y, w) | 0) + x | 0) + 1 | 0, _M0MPC15array5Array2atGiE(buf, ((Math.imul(y, w) | 0) + x | 0) + 1 | 0) + ((Math.imul(err, 7) | 0) / 16 | 0) | 0);
  }
  if ((y + 1 | 0) < h) {
    if (x > 0) {
      _M0MPC15array5Array3setGiE(buf, ((Math.imul(y + 1 | 0, w) | 0) + x | 0) - 1 | 0, _M0MPC15array5Array2atGiE(buf, ((Math.imul(y + 1 | 0, w) | 0) + x | 0) - 1 | 0) + ((Math.imul(err, 3) | 0) / 16 | 0) | 0);
    }
    _M0MPC15array5Array3setGiE(buf, (Math.imul(y + 1 | 0, w) | 0) + x | 0, _M0MPC15array5Array2atGiE(buf, (Math.imul(y + 1 | 0, w) | 0) + x | 0) + ((Math.imul(err, 5) | 0) / 16 | 0) | 0);
    if ((x + 1 | 0) < w) {
      _M0MPC15array5Array3setGiE(buf, ((Math.imul(y + 1 | 0, w) | 0) + x | 0) + 1 | 0, _M0MPC15array5Array2atGiE(buf, ((Math.imul(y + 1 | 0, w) | 0) + x | 0) + 1 | 0) + ((Math.imul(err, 1) | 0) / 16 | 0) | 0);
      return;
    } else {
      return;
    }
  } else {
    return;
  }
}
function _M0FP270717lee10pixelforge8quantize(v, levels) {
  const step = 255 / (levels - 1 | 0) | 0;
  const q = (v + (step / 2 | 0) | 0) / step | 0;
  const capped = q > (levels - 1 | 0) ? levels - 1 | 0 : q < 0 ? 0 : q;
  return (Math.imul(capped, 255) | 0) / (levels - 1 | 0) | 0;
}
function _M0MP270717lee10pixelforge5Image17dither__grayscale(self, levels) {
  const l = levels < 2 ? 2 : levels > 256 ? 256 : levels;
  const w = self.width;
  const h = self.height;
  const buf = _M0MPC15array5Array4makeGiE(Math.imul(w, h) | 0, 0);
  const _bind = Math.imul(w, h) | 0;
  let _tmp = 0;
  while (true) {
    const p = _tmp;
    if (p < _bind) {
      const base = Math.imul(p, 4) | 0;
      const _tmp$2 = self.data;
      $bound_check(_tmp$2, base);
      const _tmp$3 = Math.imul(299, _tmp$2[base]) | 0;
      const _tmp$4 = self.data;
      const _tmp$5 = base + 1 | 0;
      $bound_check(_tmp$4, _tmp$5);
      const _tmp$6 = _tmp$3 + (Math.imul(587, _tmp$4[_tmp$5]) | 0) | 0;
      const _tmp$7 = self.data;
      const _tmp$8 = base + 2 | 0;
      $bound_check(_tmp$7, _tmp$8);
      _M0MPC15array5Array3setGiE(buf, p, (_tmp$6 + (Math.imul(114, _tmp$7[_tmp$8]) | 0) | 0) / 1000 | 0);
      _tmp = p + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const out = _M0MP270717lee10pixelforge5Image3new(w, h);
  let _tmp$2 = 0;
  while (true) {
    const y = _tmp$2;
    if (y < h) {
      let _tmp$3 = 0;
      while (true) {
        const x = _tmp$3;
        if (x < w) {
          const old = _M0MPC15array5Array2atGiE(buf, (Math.imul(y, w) | 0) + x | 0);
          const newv = _M0FP270717lee10pixelforge8quantize(old, l);
          _M0FP270717lee10pixelforge7diffuse(buf, w, h, x, y, old - newv | 0);
          const b = newv < 0 ? 0 : newv > 255 ? 255 : newv & 255;
          const base = Math.imul((Math.imul(y, w) | 0) + x | 0, 4) | 0;
          const _tmp$4 = out.data;
          $bound_check(_tmp$4, base);
          _tmp$4[base] = b;
          const _tmp$5 = out.data;
          const _tmp$6 = base + 1 | 0;
          $bound_check(_tmp$5, _tmp$6);
          _tmp$5[_tmp$6] = b;
          const _tmp$7 = out.data;
          const _tmp$8 = base + 2 | 0;
          $bound_check(_tmp$7, _tmp$8);
          _tmp$7[_tmp$8] = b;
          const _tmp$9 = out.data;
          const _tmp$10 = base + 3 | 0;
          const _tmp$11 = self.data;
          const _tmp$12 = base + 3 | 0;
          $bound_check(_tmp$11, _tmp$12);
          $bound_check(_tmp$9, _tmp$10);
          _tmp$9[_tmp$10] = _tmp$11[_tmp$12];
          _tmp$3 = x + 1 | 0;
          continue;
        } else {
          break;
        }
      }
      _tmp$2 = y + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return out;
}
function _M0MP270717lee10pixelforge5Image12dither__mono(self) {
  return _M0MP270717lee10pixelforge5Image17dither__grayscale(self, 2);
}
function _M0MP270717lee10pixelforge5Image8convolve(self, kernel) {
  const out = _M0MP270717lee10pixelforge5Image3new(self.width, self.height);
  const radius = kernel.size / 2 | 0;
  const _bind = self.height;
  let _tmp = 0;
  while (true) {
    const y = _tmp;
    if (y < _bind) {
      const _bind$2 = self.width;
      let _tmp$2 = 0;
      while (true) {
        const x = _tmp$2;
        if (x < _bind$2) {
          let sum_r = 0;
          let sum_g = 0;
          let sum_b = 0;
          const _bind$3 = kernel.size;
          let _tmp$3 = 0;
          while (true) {
            const ky = _tmp$3;
            if (ky < _bind$3) {
              const _bind$4 = kernel.size;
              let _tmp$4 = 0;
              while (true) {
                const kx = _tmp$4;
                if (kx < _bind$4) {
                  const _p = (x + kx | 0) - radius | 0;
                  const _p$2 = self.width;
                  const sx = _p < 0 ? 0 : _p >= _p$2 ? _p$2 - 1 | 0 : _p;
                  const _p$3 = (y + ky | 0) - radius | 0;
                  const _p$4 = self.height;
                  const sy = _p$3 < 0 ? 0 : _p$3 >= _p$4 ? _p$4 - 1 | 0 : _p$3;
                  const w = _M0MPC15array5Array2atGdE(kernel.weights, (Math.imul(ky, kernel.size) | 0) + kx | 0);
                  const base = Math.imul((Math.imul(sy, self.width) | 0) + sx | 0, 4) | 0;
                  const _tmp$5 = sum_r;
                  const _tmp$6 = self.data;
                  $bound_check(_tmp$6, base);
                  sum_r = _tmp$5 + (_tmp$6[base] + 0) * w;
                  const _tmp$7 = sum_g;
                  const _tmp$8 = self.data;
                  const _tmp$9 = base + 1 | 0;
                  $bound_check(_tmp$8, _tmp$9);
                  sum_g = _tmp$7 + (_tmp$8[_tmp$9] + 0) * w;
                  const _tmp$10 = sum_b;
                  const _tmp$11 = self.data;
                  const _tmp$12 = base + 2 | 0;
                  $bound_check(_tmp$11, _tmp$12);
                  sum_b = _tmp$10 + (_tmp$11[_tmp$12] + 0) * w;
                  _tmp$4 = kx + 1 | 0;
                  continue;
                } else {
                  break;
                }
              }
              _tmp$3 = ky + 1 | 0;
              continue;
            } else {
              break;
            }
          }
          const base = Math.imul((Math.imul(y, self.width) | 0) + x | 0, 4) | 0;
          const _tmp$4 = out.data;
          const _p = _M0MPC16double6Double7to__int(sum_r / kernel.divisor + kernel.bias);
          $bound_check(_tmp$4, base);
          _tmp$4[base] = _p < 0 ? 0 : _p > 255 ? 255 : _p & 255;
          const _tmp$5 = out.data;
          const _tmp$6 = base + 1 | 0;
          const _p$2 = _M0MPC16double6Double7to__int(sum_g / kernel.divisor + kernel.bias);
          $bound_check(_tmp$5, _tmp$6);
          _tmp$5[_tmp$6] = _p$2 < 0 ? 0 : _p$2 > 255 ? 255 : _p$2 & 255;
          const _tmp$7 = out.data;
          const _tmp$8 = base + 2 | 0;
          const _p$3 = _M0MPC16double6Double7to__int(sum_b / kernel.divisor + kernel.bias);
          $bound_check(_tmp$7, _tmp$8);
          _tmp$7[_tmp$8] = _p$3 < 0 ? 0 : _p$3 > 255 ? 255 : _p$3 & 255;
          const _tmp$9 = out.data;
          const _tmp$10 = base + 3 | 0;
          const _tmp$11 = self.data;
          const _tmp$12 = base + 3 | 0;
          $bound_check(_tmp$11, _tmp$12);
          $bound_check(_tmp$9, _tmp$10);
          _tmp$9[_tmp$10] = _tmp$11[_tmp$12];
          _tmp$2 = x + 1 | 0;
          continue;
        } else {
          break;
        }
      }
      _tmp = y + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return out;
}
function _M0MP270717lee10pixelforge6Kernel3new(size, weights, divisor, bias) {
  if (size <= 0 || (size % 2 | 0) === 0) {
    _M0FPC15abort5abortGuE("Kernel::new: size must be a positive odd number");
  }
  if (weights.length !== (Math.imul(size, size) | 0)) {
    _M0FPC15abort5abortGuE("Kernel::new: weights length must equal size * size");
  }
  return new _M0TP270717lee10pixelforge6Kernel(size, weights, divisor, bias);
}
function _M0MP270717lee10pixelforge6Kernel14gaussian__blur() {
  return _M0MP270717lee10pixelforge6Kernel3new(3, [1, 2, 1, 2, 4, 2, 1, 2, 1], 16, 0);
}
function _M0MP270717lee10pixelforge5Image4blur(self) {
  return _M0MP270717lee10pixelforge5Image8convolve(self, _M0MP270717lee10pixelforge6Kernel14gaussian__blur());
}
function _M0MP270717lee10pixelforge5Image5canny(self, low, high) {
  const w = self.width;
  const h = self.height;
  const n = Math.imul(w, h) | 0;
  const gray = _M0MP270717lee10pixelforge5Image4blur(_M0MP270717lee10pixelforge5Image9grayscale(self));
  const gx = _M0MPC15array5Array4makeGiE(n, 0);
  const gy = _M0MPC15array5Array4makeGiE(n, 0);
  const mag = _M0MPC15array5Array4makeGiE(n, 0);
  const kx = [-1, 0, 1, -2, 0, 2, -1, 0, 1];
  const ky = [-1, -2, -1, 0, 0, 0, 1, 2, 1];
  let _tmp = 0;
  while (true) {
    const y = _tmp;
    if (y < h) {
      let _tmp$2 = 0;
      while (true) {
        const x = _tmp$2;
        if (x < w) {
          let sx = 0;
          let sy = 0;
          let _tmp$3 = 0;
          while (true) {
            const j = _tmp$3;
            if (j < 3) {
              let _tmp$4 = 0;
              while (true) {
                const i = _tmp$4;
                if (i < 3) {
                  const _p = (x + i | 0) - 1 | 0;
                  const px = _p < 0 ? 0 : _p >= w ? w - 1 | 0 : _p;
                  const _p$2 = (y + j | 0) - 1 | 0;
                  const py = _p$2 < 0 ? 0 : _p$2 >= h ? h - 1 | 0 : _p$2;
                  const _tmp$5 = gray.data;
                  const _tmp$6 = Math.imul((Math.imul(py, w) | 0) + px | 0, 4) | 0;
                  $bound_check(_tmp$5, _tmp$6);
                  const lum = _tmp$5[_tmp$6];
                  sx = sx + (Math.imul(lum, _M0MPC15array5Array2atGiE(kx, (Math.imul(j, 3) | 0) + i | 0)) | 0) | 0;
                  sy = sy + (Math.imul(lum, _M0MPC15array5Array2atGiE(ky, (Math.imul(j, 3) | 0) + i | 0)) | 0) | 0;
                  _tmp$4 = i + 1 | 0;
                  continue;
                } else {
                  break;
                }
              }
              _tmp$3 = j + 1 | 0;
              continue;
            } else {
              break;
            }
          }
          const p = (Math.imul(y, w) | 0) + x | 0;
          _M0MPC15array5Array3setGiE(gx, p, sx);
          _M0MPC15array5Array3setGiE(gy, p, sy);
          const _p = sx;
          const _tmp$4 = _p < 0 ? -_p | 0 : _p;
          const _p$2 = sy;
          _M0MPC15array5Array3setGiE(mag, p, _tmp$4 + (_p$2 < 0 ? -_p$2 | 0 : _p$2) | 0);
          _tmp$2 = x + 1 | 0;
          continue;
        } else {
          break;
        }
      }
      _tmp = y + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const thin = _M0MPC15array5Array4makeGiE(n, 0);
  let _tmp$2 = 0;
  while (true) {
    const y = _tmp$2;
    if (y < h) {
      let _tmp$3 = 0;
      while (true) {
        const x = _tmp$3;
        if (x < w) {
          _L: {
            const p = (Math.imul(y, w) | 0) + x | 0;
            const m = _M0MPC15array5Array2atGiE(mag, p);
            if (m === 0) {
              break _L;
            }
            const _p = _M0MPC15array5Array2atGiE(gx, p);
            const ax = (_p < 0 ? -_p | 0 : _p) + 0;
            const _p$2 = _M0MPC15array5Array2atGiE(gy, p);
            const ay = (_p$2 < 0 ? -_p$2 | 0 : _p$2) + 0;
            let dx = 1;
            let dy = 0;
            if (ay <= 0.41421356 * ax) {
              dx = 1;
              dy = 0;
            } else {
              if (ax <= 0.41421356 * ay) {
                dx = 0;
                dy = 1;
              } else {
                if ((Math.imul(_M0MPC15array5Array2atGiE(gx, p), _M0MPC15array5Array2atGiE(gy, p)) | 0) > 0) {
                  dx = 1;
                  dy = 1;
                } else {
                  dx = 1;
                  dy = -1;
                }
              }
            }
            const _p$3 = y + dy | 0;
            const _tmp$4 = Math.imul(_p$3 < 0 ? 0 : _p$3 >= h ? h - 1 | 0 : _p$3, w) | 0;
            const _p$4 = x + dx | 0;
            const q1 = _tmp$4 + (_p$4 < 0 ? 0 : _p$4 >= w ? w - 1 | 0 : _p$4) | 0;
            const _p$5 = y - dy | 0;
            const _tmp$5 = Math.imul(_p$5 < 0 ? 0 : _p$5 >= h ? h - 1 | 0 : _p$5, w) | 0;
            const _p$6 = x - dx | 0;
            const q2 = _tmp$5 + (_p$6 < 0 ? 0 : _p$6 >= w ? w - 1 | 0 : _p$6) | 0;
            if (m >= _M0MPC15array5Array2atGiE(mag, q1) && m >= _M0MPC15array5Array2atGiE(mag, q2)) {
              _M0MPC15array5Array3setGiE(thin, p, m);
            }
            break _L;
          }
          _tmp$3 = x + 1 | 0;
          continue;
        } else {
          break;
        }
      }
      _tmp$2 = y + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const state = _M0MPC15array5Array4makeGiE(n, 0);
  const stack = [];
  let _tmp$3 = 0;
  while (true) {
    const p = _tmp$3;
    if (p < n) {
      if (_M0MPC15array5Array2atGiE(thin, p) >= high) {
        _M0MPC15array5Array3setGiE(state, p, 2);
        _M0MPC15array5Array4pushGiE(stack, p);
      } else {
        if (_M0MPC15array5Array2atGiE(thin, p) >= low) {
          _M0MPC15array5Array3setGiE(state, p, 1);
        }
      }
      _tmp$3 = p + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  while (true) {
    if (stack.length > 0) {
      const p = _M0MPC15array5Array11unsafe__popGiE(stack);
      const px = p % w | 0;
      const py = p / w | 0;
      let _tmp$4 = -1;
      while (true) {
        const dy = _tmp$4;
        if (dy < 2) {
          let _tmp$5 = -1;
          while (true) {
            const dx = _tmp$5;
            if (dx < 2) {
              _L: {
                const nx = px + dx | 0;
                const ny = py + dy | 0;
                if (nx < 0 || (nx >= w || (ny < 0 || ny >= h))) {
                  break _L;
                }
                const q = (Math.imul(ny, w) | 0) + nx | 0;
                if (_M0MPC15array5Array2atGiE(state, q) === 1) {
                  _M0MPC15array5Array3setGiE(state, q, 2);
                  _M0MPC15array5Array4pushGiE(stack, q);
                }
                break _L;
              }
              _tmp$5 = dx + 1 | 0;
              continue;
            } else {
              break;
            }
          }
          _tmp$4 = dy + 1 | 0;
          continue;
        } else {
          break;
        }
      }
      continue;
    } else {
      break;
    }
  }
  const out = _M0MP270717lee10pixelforge5Image3new(w, h);
  let _tmp$4 = 0;
  while (true) {
    const p = _tmp$4;
    if (p < n) {
      const v = _M0MPC15array5Array2atGiE(state, p) === 2 ? 255 : 0;
      const base = Math.imul(p, 4) | 0;
      const _tmp$5 = out.data;
      $bound_check(_tmp$5, base);
      _tmp$5[base] = v;
      const _tmp$6 = out.data;
      const _tmp$7 = base + 1 | 0;
      $bound_check(_tmp$6, _tmp$7);
      _tmp$6[_tmp$7] = v;
      const _tmp$8 = out.data;
      const _tmp$9 = base + 2 | 0;
      $bound_check(_tmp$8, _tmp$9);
      _tmp$8[_tmp$9] = v;
      const _tmp$10 = out.data;
      const _tmp$11 = base + 3 | 0;
      const _tmp$12 = self.data;
      const _tmp$13 = base + 3 | 0;
      $bound_check(_tmp$12, _tmp$13);
      $bound_check(_tmp$10, _tmp$11);
      _tmp$10[_tmp$11] = _tmp$12[_tmp$13];
      _tmp$4 = p + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return out;
}
function _M0MP270717lee10pixelforge6Kernel5edges() {
  return _M0MP270717lee10pixelforge6Kernel3new(3, [-1, -1, -1, -1, 8, -1, -1, -1, -1], 1, 0);
}
function _M0MP270717lee10pixelforge5Image5edges(self) {
  return _M0MP270717lee10pixelforge5Image8convolve(self, _M0MP270717lee10pixelforge6Kernel5edges());
}
function _M0MP270717lee10pixelforge6Kernel6emboss() {
  return _M0MP270717lee10pixelforge6Kernel3new(3, [-2, -1, 0, -1, 1, 1, 0, 1, 2], 1, 128);
}
function _M0MP270717lee10pixelforge5Image6emboss(self) {
  return _M0MP270717lee10pixelforge5Image8convolve(self, _M0MP270717lee10pixelforge6Kernel6emboss());
}
function _M0MP270717lee10pixelforge5Image15gradient__edges(self, gx, gy) {
  const gray = _M0MP270717lee10pixelforge5Image9grayscale(self);
  const out = _M0MP270717lee10pixelforge5Image3new(self.width, self.height);
  const _bind = self.height;
  let _tmp = 0;
  while (true) {
    const y = _tmp;
    if (y < _bind) {
      const _bind$2 = self.width;
      let _tmp$2 = 0;
      while (true) {
        const x = _tmp$2;
        if (x < _bind$2) {
          let sx = 0;
          let sy = 0;
          let _tmp$3 = 0;
          while (true) {
            const ky = _tmp$3;
            if (ky < 3) {
              let _tmp$4 = 0;
              while (true) {
                const kx = _tmp$4;
                if (kx < 3) {
                  const _p = (x + kx | 0) - 1 | 0;
                  const _p$2 = self.width;
                  const px = _p < 0 ? 0 : _p >= _p$2 ? _p$2 - 1 | 0 : _p;
                  const _p$3 = (y + ky | 0) - 1 | 0;
                  const _p$4 = self.height;
                  const py = _p$3 < 0 ? 0 : _p$3 >= _p$4 ? _p$4 - 1 | 0 : _p$3;
                  const base = Math.imul((Math.imul(py, self.width) | 0) + px | 0, 4) | 0;
                  const _tmp$5 = gray.data;
                  $bound_check(_tmp$5, base);
                  const lum = _tmp$5[base];
                  const k = (Math.imul(ky, 3) | 0) + kx | 0;
                  sx = sx + (Math.imul(lum, _M0MPC15array5Array2atGiE(gx, k)) | 0) | 0;
                  sy = sy + (Math.imul(lum, _M0MPC15array5Array2atGiE(gy, k)) | 0) | 0;
                  _tmp$4 = kx + 1 | 0;
                  continue;
                } else {
                  break;
                }
              }
              _tmp$3 = ky + 1 | 0;
              continue;
            } else {
              break;
            }
          }
          const _p = sx;
          const _tmp$4 = _p < 0 ? -_p | 0 : _p;
          const _p$2 = sy;
          const _p$3 = _tmp$4 + (_p$2 < 0 ? -_p$2 | 0 : _p$2) | 0;
          const v = _p$3 < 0 ? 0 : _p$3 > 255 ? 255 : _p$3 & 255;
          const base = Math.imul((Math.imul(y, self.width) | 0) + x | 0, 4) | 0;
          const _tmp$5 = out.data;
          $bound_check(_tmp$5, base);
          _tmp$5[base] = v;
          const _tmp$6 = out.data;
          const _tmp$7 = base + 1 | 0;
          $bound_check(_tmp$6, _tmp$7);
          _tmp$6[_tmp$7] = v;
          const _tmp$8 = out.data;
          const _tmp$9 = base + 2 | 0;
          $bound_check(_tmp$8, _tmp$9);
          _tmp$8[_tmp$9] = v;
          const _tmp$10 = out.data;
          const _tmp$11 = base + 3 | 0;
          const _tmp$12 = self.data;
          const _tmp$13 = base + 3 | 0;
          $bound_check(_tmp$12, _tmp$13);
          $bound_check(_tmp$10, _tmp$11);
          _tmp$10[_tmp$11] = _tmp$12[_tmp$13];
          _tmp$2 = x + 1 | 0;
          continue;
        } else {
          break;
        }
      }
      _tmp = y + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return out;
}
function _M0MP270717lee10pixelforge5Image6scharr(self) {
  return _M0MP270717lee10pixelforge5Image15gradient__edges(self, [-3, 0, 3, -10, 0, 10, -3, 0, 3], [-3, -10, -3, 0, 0, 0, 3, 10, 3]);
}
function _M0MP270717lee10pixelforge6Kernel7sharpen() {
  return _M0MP270717lee10pixelforge6Kernel3new(3, [0, -1, 0, -1, 5, -1, 0, -1, 0], 1, 0);
}
function _M0MP270717lee10pixelforge5Image7sharpen(self) {
  return _M0MP270717lee10pixelforge5Image8convolve(self, _M0MP270717lee10pixelforge6Kernel7sharpen());
}
function _M0MP270717lee10pixelforge5Image5sobel(self) {
  return _M0MP270717lee10pixelforge5Image15gradient__edges(self, [-1, 0, 1, -2, 0, 2, -1, 0, 1], [-1, -2, -1, 0, 0, 0, 1, 2, 1]);
}
function _M0MP270717lee10pixelforge5Image17apply__filter__id(self, filter_id, amount) {
  switch (filter_id) {
    case 0: {
      return _M0MP270717lee10pixelforge5Image9grayscale(self);
    }
    case 1: {
      return _M0MP270717lee10pixelforge5Image6invert(self);
    }
    case 2: {
      return _M0MP270717lee10pixelforge5Image10brightness(self, _M0MPC16double6Double7to__int(amount));
    }
    case 3: {
      return _M0MP270717lee10pixelforge5Image8contrast(self, amount);
    }
    case 4: {
      return _M0MP270717lee10pixelforge5Image4blur(self);
    }
    case 5: {
      return _M0MP270717lee10pixelforge5Image7sharpen(self);
    }
    case 6: {
      return _M0MP270717lee10pixelforge5Image6emboss(self);
    }
    case 7: {
      return _M0MP270717lee10pixelforge5Image5edges(self);
    }
    case 8: {
      return _M0MP270717lee10pixelforge5Image5sobel(self);
    }
    case 9: {
      return _M0MP270717lee10pixelforge5Image5sepia(self);
    }
    case 10: {
      return _M0MP270717lee10pixelforge5Image9threshold(self, _M0MPC16double6Double7to__int(amount) <= 0 ? 128 : _M0MPC16double6Double7to__int(amount));
    }
    case 11: {
      return _M0MP270717lee10pixelforge5Image8pixelate(self, _M0MPC16double6Double7to__int(amount) < 2 ? 8 : _M0MPC16double6Double7to__int(amount));
    }
    case 12: {
      return _M0MP270717lee10pixelforge5Image6median(self);
    }
    case 13: {
      return _M0MP270717lee10pixelforge5Image19histogram__equalize(self);
    }
    case 14: {
      return _M0MP270717lee10pixelforge5Image16flip__horizontal(self);
    }
    case 15: {
      return _M0MP270717lee10pixelforge5Image14flip__vertical(self);
    }
    case 16: {
      return _M0MP270717lee10pixelforge5Image9posterize(self, _M0MPC16double6Double7to__int(amount) < 2 ? 4 : _M0MPC16double6Double7to__int(amount));
    }
    case 17: {
      return _M0MP270717lee10pixelforge5Image5gamma(self, amount <= 0 ? 2.2 : amount);
    }
    case 18: {
      return _M0MP270717lee10pixelforge5Image8vignette(self, amount <= 0 ? 0.5 : amount);
    }
    case 19: {
      return _M0MP270717lee10pixelforge5Image6scharr(self);
    }
    case 20: {
      const high = _M0MPC16double6Double7to__int(amount) <= 0 ? 100 : _M0MPC16double6Double7to__int(amount);
      return _M0MP270717lee10pixelforge5Image5canny(self, high / 2 | 0, high);
    }
    case 21: {
      return _M0MP270717lee10pixelforge5Image4otsu(self);
    }
    case 22: {
      return _M0MP270717lee10pixelforge5Image12dither__mono(self);
    }
    default: {
      return _M0MP270717lee10pixelforge5Image4copy(self);
    }
  }
}
function _M0FP370717lee10pixelforge3web13apply__filter(data, width, height, filter_id, amount) {
  return _M0MP270717lee10pixelforge5Image17apply__filter__id(_M0MP270717lee10pixelforge5Image11from__bytes(width, height, data), filter_id, amount).data;
}
function _M0FP370717lee10pixelforge3web11encode__png(data, width, height) {
  const bytes = _M0FP270717lee10pixelforge11png__encode(_M0MP270717lee10pixelforge5Image11from__bytes(width, height, data));
  const out = $makebytes(bytes.length, 0);
  const _bind = bytes.length;
  let _tmp = 0;
  while (true) {
    const i = _tmp;
    if (i < _bind) {
      $bound_check(out, i);
      out[i] = _M0MPC15array5Array2atGyE(bytes, i);
      _tmp = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return out;
}
export { _M0FP370717lee10pixelforge3web13apply__filter as apply_filter, _M0FP370717lee10pixelforge3web11encode__png as encode_png }
