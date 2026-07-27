class $PanicError extends Error {}
function $panic() {
  throw new $PanicError();
}
const _M0MPB7JSArray4copy = (arr) => arr.slice(0);
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
function _M0MPC15array10FixedArray4copyGyE(self) {
  return _M0MPB7JSArray4copy(self);
}
function _M0MPC16double6Double7to__int(self) {
  return self !== self ? 0 : self >= 2147483647 ? 2147483647 : self <= -2147483648 ? -2147483648 : self | 0;
}
function _M0MPC15array5Array2atGdE(self, index) {
  const len = self.length;
  return index >= 0 && index < len ? self[index] : $panic();
}
function _M0MPC15array5Array2atGiE(self, index) {
  const len = self.length;
  return index >= 0 && index < len ? self[index] : $panic();
}
function _M0FPC14math3pow(_tmp, _tmp$2) {
  return Math.pow(_tmp, _tmp$2);
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
function _M0MP270717lee10pixelforge5Image11from__bytes(width, height, data) {
  if (data.length !== (Math.imul(Math.imul(width, height) | 0, 4) | 0)) {
    _M0FPC15abort5abortGuE("Image::from_bytes: buffer length must equal width * height * 4");
  }
  return new _M0TP270717lee10pixelforge5Image(width, height, data);
}
function _M0MP270717lee10pixelforge5Image4copy(self) {
  return new _M0TP270717lee10pixelforge5Image(self.width, self.height, _M0MPC15array10FixedArray4copyGyE(self.data));
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
function _M0MP270717lee10pixelforge5Image8contrastN5applyS143(factor, c) {
  return _M0MPC16double6Double7to__int((c + 0 - 128) * factor + 128);
}
function _M0MP270717lee10pixelforge5Image8contrast(self, factor) {
  return _M0MP270717lee10pixelforge5Image8map__rgb(self, (r, g, b) => ({ _0: _M0MP270717lee10pixelforge5Image8contrastN5applyS143(factor, r), _1: _M0MP270717lee10pixelforge5Image8contrastN5applyS143(factor, g), _2: _M0MP270717lee10pixelforge5Image8contrastN5applyS143(factor, b) }));
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
    default: {
      return _M0MP270717lee10pixelforge5Image4copy(self);
    }
  }
}
function _M0FP370717lee10pixelforge3web13apply__filter(data, width, height, filter_id, amount) {
  return _M0MP270717lee10pixelforge5Image17apply__filter__id(_M0MP270717lee10pixelforge5Image11from__bytes(width, height, data), filter_id, amount).data;
}
export { _M0FP370717lee10pixelforge3web13apply__filter as apply_filter }
