var $reinterpret_view = new DataView(new ArrayBuffer(8));
function $i64_reinterpret_f64(a) {
  $reinterpret_view.setBigUint64(0, BigInt.asUintN(64, a), false);
  return $reinterpret_view.getFloat64(0, false);
}
function $oob() {
  throw new Error("Index out of bounds");
}
class $PanicError extends Error {}
function $panic(message) {
  throw new $PanicError(message);
}
function _M0TPB13StringBuilder(param0) {
  this.val = param0;
}
function _M0TPC16string10StringView(param0, param1, param2) {
  this.str = param0;
  this.start = param1;
  this.end = param2;
}
var _M0FPB19int__to__string__js = (x, radix) => {
  return x.toString(radix);
};
function $makebytes(a, b) {
  const arr = new Uint8Array(a);
  if (b !== 0) {
    arr.fill(b);
  }
  return arr;
}
function _M0TPB5ArrayGiE(param0, param1) {
  this.buf = param0;
  this.len = param1;
}
function _M0TP270717lee10pixelforge5Image(param0, param1, param2) {
  this.width = param0;
  this.height = param1;
  this.data = param2;
}
function _M0TP270717lee10pixelforge9BitWriter(param0, param1, param2) {
  this.out = param0;
  this.current = param1;
  this.bits = param2;
}
function _M0TPB5ArrayGyE(param0, param1) {
  this.buf = param0;
  this.len = param1;
}
function _M0TP270717lee10pixelforge6Kernel(param0, param1, param2, param3) {
  this.size = param0;
  this.weights = param1;
  this.divisor = param2;
  this.bias = param3;
}
function _M0TPB5ArrayGdE(param0, param1) {
  this.buf = param0;
  this.len = param1;
}
function $make_array_len_and_init(a, b) {
  const arr = new Array(a);
  arr.fill(b);
  return arr;
}
var _M0FP092moonbitlang_2fcore_2fbuiltin_2fStringBuilder_24as_24_40moonbitlang_2fcore_2fbuiltin_2eLogger = { method_0: _M0IPB13StringBuilderPB6Logger13write__string, method_1: _M0IP016_24default__implPB6Logger16write__substringGRPB13StringBuilderE, method_2: _M0IPB13StringBuilderPB6Logger11write__view, method_3: _M0IPB13StringBuilderPB6Logger11write__char, method_4: _M0IP016_24default__implPB6Logger28write__string__interpolationGRPB13StringBuilderE, method_5: _M0IP016_24default__implPB6Logger5writeGRPB13StringBuilderE };
var _M0FPB18double__max__value = $i64_reinterpret_f64(9218868437227405311n);
var _M0FPB18double__min__value = $i64_reinterpret_f64(18442240474082181119n);
var _M0FPC16double8infinity = $i64_reinterpret_f64(9218868437227405312n);
var _M0FPC16double13neg__infinity = $i64_reinterpret_f64(18442240474082181120n);
function _M0MPC15array10FixedArray12unsafe__blitGyE(dst, dst_offset, src, src_offset, len) {
  if (dst === src && dst_offset < src_offset) {
    let _tmp = 0;
    while (true) {
      const i = _tmp;
      if (i < len) {
        const _tmp$2 = dst_offset + i | 0;
        const _tmp$3 = src_offset + i | 0;
        if (_tmp$2 >>> 0 < dst.length) {
          dst[_tmp$2] = _tmp$3 >>> 0 < src.length ? src[_tmp$3] : $oob();
        } else {
          $oob();
        }
        _tmp = i + 1 | 0;
        continue;
      } else {
        return;
      }
    }
  } else {
    let _tmp = len - 1 | 0;
    let _tmp$2 = len > 0;
    while (true) {
      const i = _tmp;
      const _more = _tmp$2;
      if (_more) {
        const _tmp$3 = dst_offset + i | 0;
        const _tmp$4 = src_offset + i | 0;
        if (_tmp$3 >>> 0 < dst.length) {
          dst[_tmp$3] = _tmp$4 >>> 0 < src.length ? src[_tmp$4] : $oob();
        } else {
          $oob();
        }
        _tmp = i - 1 | 0;
        _tmp$2 = i > 0;
        continue;
      } else {
        return;
      }
    }
  }
}
function _M0MPC15array10FixedArray12unsafe__blitGRPB17UnsafeMaybeUninitGiEE(dst, dst_offset, src, src_offset, len) {
  if (dst === src && dst_offset < src_offset) {
    let _tmp = 0;
    while (true) {
      const i = _tmp;
      if (i < len) {
        const _tmp$2 = dst_offset + i | 0;
        const _tmp$3 = src_offset + i | 0;
        if (_tmp$2 >>> 0 < dst.length) {
          dst[_tmp$2] = _tmp$3 >>> 0 < src.length ? src[_tmp$3] : $oob();
        } else {
          $oob();
        }
        _tmp = i + 1 | 0;
        continue;
      } else {
        return;
      }
    }
  } else {
    let _tmp = len - 1 | 0;
    let _tmp$2 = len > 0;
    while (true) {
      const i = _tmp;
      const _more = _tmp$2;
      if (_more) {
        const _tmp$3 = dst_offset + i | 0;
        const _tmp$4 = src_offset + i | 0;
        if (_tmp$3 >>> 0 < dst.length) {
          dst[_tmp$3] = _tmp$4 >>> 0 < src.length ? src[_tmp$4] : $oob();
        } else {
          $oob();
        }
        _tmp = i - 1 | 0;
        _tmp$2 = i > 0;
        continue;
      } else {
        return;
      }
    }
  }
}
function _M0MPC15array10FixedArray12unsafe__blitGRPB17UnsafeMaybeUninitGyEE(dst, dst_offset, src, src_offset, len) {
  if (dst === src && dst_offset < src_offset) {
    let _tmp = 0;
    while (true) {
      const i = _tmp;
      if (i < len) {
        const _tmp$2 = dst_offset + i | 0;
        const _tmp$3 = src_offset + i | 0;
        if (_tmp$2 >>> 0 < dst.length) {
          dst[_tmp$2] = _tmp$3 >>> 0 < src.length ? src[_tmp$3] : $oob();
        } else {
          $oob();
        }
        _tmp = i + 1 | 0;
        continue;
      } else {
        return;
      }
    }
  } else {
    let _tmp = len - 1 | 0;
    let _tmp$2 = len > 0;
    while (true) {
      const i = _tmp;
      const _more = _tmp$2;
      if (_more) {
        const _tmp$3 = dst_offset + i | 0;
        const _tmp$4 = src_offset + i | 0;
        if (_tmp$3 >>> 0 < dst.length) {
          dst[_tmp$3] = _tmp$4 >>> 0 < src.length ? src[_tmp$4] : $oob();
        } else {
          $oob();
        }
        _tmp = i - 1 | 0;
        _tmp$2 = i > 0;
        continue;
      } else {
        return;
      }
    }
  }
}
function _M0MPB18UninitializedArray12unsafe__blitGyE(dst, dst_offset, src, src_offset, len) {
  _M0MPC15array10FixedArray12unsafe__blitGRPB17UnsafeMaybeUninitGyEE(dst, dst_offset, src, src_offset, len);
}
function _M0MPB18UninitializedArray12unsafe__blitGiE(dst, dst_offset, src, src_offset, len) {
  _M0MPC15array10FixedArray12unsafe__blitGRPB17UnsafeMaybeUninitGiEE(dst, dst_offset, src, src_offset, len);
}
function _M0MPB18UninitializedArray23unsafe__make__and__blitGyE(src, allocate_len, src_offset, dst_offset, blit_len) {
  const dst = new Uint8Array(allocate_len);
  _M0MPB18UninitializedArray12unsafe__blitGyE(dst, dst_offset, src, src_offset, blit_len);
  return dst;
}
function _M0MPB18UninitializedArray23unsafe__make__and__blitGiE(src, allocate_len, src_offset, dst_offset, blit_len) {
  const dst = new Array(allocate_len);
  _M0MPB18UninitializedArray12unsafe__blitGiE(dst, dst_offset, src, src_offset, blit_len);
  return dst;
}
function _M0MPB13StringBuilder13write__objectGiE(self, obj) {
  _M0IP016_24default__implPB4Show6outputGiE(obj, { self: self, method_table: _M0FP092moonbitlang_2fcore_2fbuiltin_2fStringBuilder_24as_24_40moonbitlang_2fcore_2fbuiltin_2eLogger });
}
function _M0MPB18UninitializedArray23make__and__blit_2einnerGyE(src, allocate_len, len, src_offset, dst_offset) {
  let _tmp;
  if (allocate_len >= 0) {
    let _tmp$2;
    if (len >= 0) {
      let _tmp$3;
      const _p = src.length;
      if (src_offset >= 0 && src_offset <= (_p - len | 0)) {
        _tmp$3 = dst_offset >= 0 && dst_offset <= (allocate_len - len | 0);
      } else {
        _tmp$3 = false;
      }
      _tmp$2 = _tmp$3;
    } else {
      _tmp$2 = false;
    }
    _tmp = _tmp$2;
  } else {
    _tmp = false;
  }
  if (_tmp) {
    return _M0MPB18UninitializedArray23unsafe__make__and__blitGyE(src, allocate_len, src_offset, dst_offset, len);
  } else {
    const _string_builder = _M0MPB13StringBuilder21StringBuilder_2einner(8);
    const _p = "bounds check failed: allocate_len = ";
    _string_builder.val = `${_string_builder.val}${_p}`;
    _M0MPB13StringBuilder13write__objectGiE(_string_builder, allocate_len);
    const _p$2 = ", src_offset = ";
    _string_builder.val = `${_string_builder.val}${_p$2}`;
    _M0MPB13StringBuilder13write__objectGiE(_string_builder, src_offset);
    const _p$3 = ", dst_offset = ";
    _string_builder.val = `${_string_builder.val}${_p$3}`;
    _M0MPB13StringBuilder13write__objectGiE(_string_builder, dst_offset);
    const _p$4 = ", len = ";
    _string_builder.val = `${_string_builder.val}${_p$4}`;
    _M0MPB13StringBuilder13write__objectGiE(_string_builder, len);
    const _p$5 = ", src.length = ";
    _string_builder.val = `${_string_builder.val}${_p$5}`;
    _M0MPB13StringBuilder13write__objectGiE(_string_builder, src.length);
    return $panic(_string_builder.val);
  }
}
function _M0MPB18UninitializedArray23make__and__blit_2einnerGiE(src, allocate_len, len, src_offset, dst_offset) {
  let _tmp;
  if (allocate_len >= 0) {
    let _tmp$2;
    if (len >= 0) {
      let _tmp$3;
      const _p = src.length;
      if (src_offset >= 0 && src_offset <= (_p - len | 0)) {
        _tmp$3 = dst_offset >= 0 && dst_offset <= (allocate_len - len | 0);
      } else {
        _tmp$3 = false;
      }
      _tmp$2 = _tmp$3;
    } else {
      _tmp$2 = false;
    }
    _tmp = _tmp$2;
  } else {
    _tmp = false;
  }
  if (_tmp) {
    return _M0MPB18UninitializedArray23unsafe__make__and__blitGiE(src, allocate_len, src_offset, dst_offset, len);
  } else {
    const _string_builder = _M0MPB13StringBuilder21StringBuilder_2einner(8);
    const _p = "bounds check failed: allocate_len = ";
    _string_builder.val = `${_string_builder.val}${_p}`;
    _M0MPB13StringBuilder13write__objectGiE(_string_builder, allocate_len);
    const _p$2 = ", src_offset = ";
    _string_builder.val = `${_string_builder.val}${_p$2}`;
    _M0MPB13StringBuilder13write__objectGiE(_string_builder, src_offset);
    const _p$3 = ", dst_offset = ";
    _string_builder.val = `${_string_builder.val}${_p$3}`;
    _M0MPB13StringBuilder13write__objectGiE(_string_builder, dst_offset);
    const _p$4 = ", len = ";
    _string_builder.val = `${_string_builder.val}${_p$4}`;
    _M0MPB13StringBuilder13write__objectGiE(_string_builder, len);
    const _p$5 = ", src.length = ";
    _string_builder.val = `${_string_builder.val}${_p$5}`;
    _M0MPB13StringBuilder13write__objectGiE(_string_builder, src.length);
    return $panic(_string_builder.val);
  }
}
function _M0MPB13StringBuilder21StringBuilder_2einner(capacity) {
  return capacity >= 0 ? new _M0TPB13StringBuilder("") : $panic("capacity must be non-negative");
}
function _M0IPB13StringBuilderPB6Logger11write__char(self, ch) {
  self.val = `${self.val}${String.fromCodePoint(ch)}`;
}
function _M0IPB13StringBuilderPB6Logger13write__string(self, str) {
  self.val = `${self.val}${str}`;
}
function _M0IP016_24default__implPB6Logger28write__string__interpolationGRPB13StringBuilderE(self, show) {
  show.method_table.method_0(show.self, { self: self, method_table: _M0FP092moonbitlang_2fcore_2fbuiltin_2fStringBuilder_24as_24_40moonbitlang_2fcore_2fbuiltin_2eLogger });
}
function _M0IP016_24default__implPB6Logger5writeGRPB13StringBuilderE(self, show) {
  show.method_table.method_0(show.self, { self: self, method_table: _M0FP092moonbitlang_2fcore_2fbuiltin_2fStringBuilder_24as_24_40moonbitlang_2fcore_2fbuiltin_2eLogger });
}
function _M0MPC16string6String21clamped__view_2einner(self, start, end) {
  const len = self.length;
  let lo;
  if (start <= 0) {
    lo = 0;
  } else {
    if (start >= len) {
      lo = len;
    } else {
      let _tmp;
      const _p = self.charCodeAt(start);
      if (_p >= 56320 && _p <= 57343) {
        const _p$2 = self.charCodeAt(start - 1 | 0);
        _tmp = _p$2 >= 55296 && _p$2 <= 56319;
      } else {
        _tmp = false;
      }
      if (_tmp) {
        lo = start + 1 | 0;
      } else {
        lo = start;
      }
    }
  }
  let hi;
  if (end === undefined) {
    hi = len;
  } else {
    const _Some = end;
    const _e = _Some;
    if (_e <= 0) {
      hi = 0;
    } else {
      if (_e >= len) {
        hi = len;
      } else {
        let _tmp;
        const _p = self.charCodeAt(_e);
        if (_p >= 56320 && _p <= 57343) {
          const _p$2 = self.charCodeAt(_e - 1 | 0);
          _tmp = _p$2 >= 55296 && _p$2 <= 56319;
        } else {
          _tmp = false;
        }
        if (_tmp) {
          hi = _e - 1 | 0;
        } else {
          hi = _e;
        }
      }
    }
  }
  return lo >= hi ? new _M0TPC16string10StringView(self, lo, lo) : new _M0TPC16string10StringView(self, lo, hi);
}
function _M0IP016_24default__implPB6Logger16write__substringGRPB13StringBuilderE(self, value, start, len) {
  _M0IPB13StringBuilderPB6Logger11write__view(self, _M0MPC16string6String21clamped__view_2einner(value, start, start + len | 0));
}
function _M0IP016_24default__implPB4Show6outputGiE(self, logger) {
  logger.method_table.method_0(logger.self, _M0IPC13int3IntPB4Show10to__string(self));
}
function _M0MPC13int3Int18to__string_2einner(self, radix) {
  return _M0FPB19int__to__string__js(self, radix);
}
function _M0MPC16string10StringView9to__owned(self) {
  return self.str.substring(self.start, self.end);
}
function _M0IPB13StringBuilderPB6Logger11write__view(self, str) {
  self.val = `${self.val}${_M0MPC16string10StringView9to__owned(str)}`;
}
function _M0FPB23array__growth__capacity(current, len, required) {
  if (required < len) {
    $panic("Array capacity overflow");
  }
  const start = current === 0 ? 8 : current;
  let _tmp = start;
  while (true) {
    const space = _tmp;
    if (space < required) {
      const next = Math.imul(space, 2) | 0;
      if (next <= space) {
        return required;
      }
      _tmp = next;
      continue;
    } else {
      return space;
    }
  }
}
function _M0MPC15array5Array8capacityGyE(self) {
  return self.buf.length;
}
function _M0MPC15array5Array8capacityGiE(self) {
  return self.buf.length;
}
function _M0MPC15array5Array14resize__bufferGyE(self, new_capacity) {
  const old_buf = self.buf;
  self.buf = new Uint8Array([]);
  const len = self.len;
  const copy_len = len < new_capacity ? len : new_capacity;
  const new_buf = _M0MPB18UninitializedArray23make__and__blit_2einnerGyE(old_buf, new_capacity, copy_len, 0, 0);
  self.buf = new_buf;
}
function _M0MPC15array5Array14resize__bufferGiE(self, new_capacity) {
  const old_buf = self.buf;
  self.buf = [];
  const len = self.len;
  const copy_len = len < new_capacity ? len : new_capacity;
  const new_buf = _M0MPB18UninitializedArray23make__and__blit_2einnerGiE(old_buf, new_capacity, copy_len, 0, 0);
  self.buf = new_buf;
}
function _M0MPC15array5Array7reallocGyE(self, required) {
  const old_cap = _M0MPC15array5Array8capacityGyE(self);
  const new_cap = _M0FPB23array__growth__capacity(old_cap, self.len, required);
  _M0MPC15array5Array14resize__bufferGyE(self, new_cap);
}
function _M0MPC15array5Array7reallocGiE(self, required) {
  const old_cap = _M0MPC15array5Array8capacityGiE(self);
  const new_cap = _M0FPB23array__growth__capacity(old_cap, self.len, required);
  _M0MPC15array5Array14resize__bufferGiE(self, new_cap);
}
function _M0MPC15array5Array4pushGyE(self, value) {
  if (self.len === self.buf.length) {
    _M0MPC15array5Array7reallocGyE(self, self.len + 1 | 0);
  }
  const length = self.len;
  self.buf[length] = value;
  self.len = length + 1 | 0;
}
function _M0MPC15array5Array4pushGiE(self, value) {
  if (self.len === self.buf.length) {
    _M0MPC15array5Array7reallocGiE(self, self.len + 1 | 0);
  }
  const length = self.len;
  self.buf[length] = value;
  self.len = length + 1 | 0;
}
function _M0IPC13int3IntPB4Show10to__string(self) {
  return _M0MPC13int3Int18to__string_2einner(self, 10);
}
function _M0MPC15array5Array20unsafe__make__uninitGiE(len) {
  return new _M0TPB5ArrayGiE(new Array(len), len);
}
function _M0MPC15array10FixedArray23unsafe__make__and__blitGyE(src, allocate_len, init, src_offset, dst_offset, blit_len) {
  const dst = $makebytes(allocate_len, init);
  _M0MPC15array10FixedArray12unsafe__blitGyE(dst, dst_offset, src, src_offset, blit_len);
  return dst;
}
function _M0MPC15array10FixedArray23make__and__blit_2einnerGyE(src, allocate_len, init, len, src_offset, dst_offset) {
  let _tmp;
  if (allocate_len >= 0) {
    let _tmp$2;
    if (len >= 0) {
      let _tmp$3;
      const _p = src.length;
      if (src_offset >= 0 && src_offset <= (_p - len | 0)) {
        _tmp$3 = dst_offset >= 0 && dst_offset <= (allocate_len - len | 0);
      } else {
        _tmp$3 = false;
      }
      _tmp$2 = _tmp$3;
    } else {
      _tmp$2 = false;
    }
    _tmp = _tmp$2;
  } else {
    _tmp = false;
  }
  if (_tmp) {
    return _M0MPC15array10FixedArray23unsafe__make__and__blitGyE(src, allocate_len, init, src_offset, dst_offset, len);
  } else {
    const _string_builder = _M0MPB13StringBuilder21StringBuilder_2einner(8);
    const _p = "bounds check failed: allocate_len = ";
    _string_builder.val = `${_string_builder.val}${_p}`;
    _M0MPB13StringBuilder13write__objectGiE(_string_builder, allocate_len);
    const _p$2 = ", src_offset = ";
    _string_builder.val = `${_string_builder.val}${_p$2}`;
    _M0MPB13StringBuilder13write__objectGiE(_string_builder, src_offset);
    const _p$3 = ", dst_offset = ";
    _string_builder.val = `${_string_builder.val}${_p$3}`;
    _M0MPB13StringBuilder13write__objectGiE(_string_builder, dst_offset);
    const _p$4 = ", len = ";
    _string_builder.val = `${_string_builder.val}${_p$4}`;
    _M0MPB13StringBuilder13write__objectGiE(_string_builder, len);
    const _p$5 = ", src.length = ";
    _string_builder.val = `${_string_builder.val}${_p$5}`;
    _M0MPB13StringBuilder13write__objectGiE(_string_builder, src.length);
    return $panic(_string_builder.val);
  }
}
function _M0MPC15array10FixedArray4copyGyE(self) {
  const len = self.length;
  return len === 0 ? new Uint8Array([]) : _M0MPC15array10FixedArray23make__and__blit_2einnerGyE(self, len, 0 >>> 0 < self.length ? self[0] : $oob(), len, 0, 0);
}
function _M0MPC16double6Double7to__int(self) {
  return self !== self ? 0 : self >= 2147483647 ? 2147483647 : self <= -2147483648 ? -2147483648 : self | 0;
}
function _M0MPC15array5Array4makeGiE(len, elem) {
  const arr = _M0MPC15array5Array20unsafe__make__uninitGiE(len);
  let _tmp = 0;
  while (true) {
    const i = _tmp;
    if (i < len) {
      arr.buf[i] = elem;
      _tmp = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return arr;
}
function _M0MPC15array5Array11unsafe__popGiE(self) {
  const len = self.len;
  if (len !== 0) {
    const index = len - 1 | 0;
    const v = self.buf[index];
    self.len = index;
    return v;
  } else {
    return $panic();
  }
}
function _M0FPC14math13math__pow__js(_tmp, _tmp$2) {
  return Math.pow(_tmp, _tmp$2);
}
function _M0FPC14math3pow(base, exponent) {
  if (base === 1) {
    return 1;
  }
  if (base === -1 && (exponent === _M0FPC16double8infinity || exponent === _M0FPC16double13neg__infinity)) {
    return 1;
  }
  return _M0FPC14math13math__pow__js(base, exponent);
}
function _M0FP270717lee10pixelforge20checked__buffer__len(width, height) {
  if (width < 0 || height < 0) {
    $panic("Image: width and height must be non-negative");
  }
  if (width === 0 || height === 0) {
    return 0;
  }
  if (width > (100000000 / height | 0)) {
    $panic("Image: dimensions exceed the maximum pixel count");
  }
  const pixels = Math.imul(width, height) | 0;
  return Math.imul(pixels, 4) | 0;
}
function _M0MP270717lee10pixelforge5Image3new(width, height) {
  const len = _M0FP270717lee10pixelforge20checked__buffer__len(width, height);
  return new _M0TP270717lee10pixelforge5Image(width, height, $makebytes(len, 0));
}
function _M0MP270717lee10pixelforge5Image4copy(self) {
  return new _M0TP270717lee10pixelforge5Image(self.width, self.height, _M0MPC15array10FixedArray4copyGyE(self.data));
}
function _M0MP270717lee10pixelforge5Image12pixel__count(self) {
  return _M0FP270717lee10pixelforge20checked__buffer__len(self.width, self.height) / 4 | 0;
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
          if (dst >>> 0 < _tmp$3.length) {
            _tmp$3[dst] = src >>> 0 < _tmp$4.length ? _tmp$4[src] : $oob();
          } else {
            $oob();
          }
          const _tmp$5 = out.data;
          const _tmp$6 = dst + 1 | 0;
          const _tmp$7 = self.data;
          const _tmp$8 = src + 1 | 0;
          if (_tmp$6 >>> 0 < _tmp$5.length) {
            _tmp$5[_tmp$6] = _tmp$8 >>> 0 < _tmp$7.length ? _tmp$7[_tmp$8] : $oob();
          } else {
            $oob();
          }
          const _tmp$9 = out.data;
          const _tmp$10 = dst + 2 | 0;
          const _tmp$11 = self.data;
          const _tmp$12 = src + 2 | 0;
          if (_tmp$10 >>> 0 < _tmp$9.length) {
            _tmp$9[_tmp$10] = _tmp$12 >>> 0 < _tmp$11.length ? _tmp$11[_tmp$12] : $oob();
          } else {
            $oob();
          }
          const _tmp$13 = out.data;
          const _tmp$14 = dst + 3 | 0;
          const _tmp$15 = self.data;
          const _tmp$16 = src + 3 | 0;
          if (_tmp$14 >>> 0 < _tmp$13.length) {
            _tmp$13[_tmp$14] = _tmp$16 >>> 0 < _tmp$15.length ? _tmp$15[_tmp$16] : $oob();
          } else {
            $oob();
          }
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
          if (dst >>> 0 < _tmp$3.length) {
            _tmp$3[dst] = src >>> 0 < _tmp$4.length ? _tmp$4[src] : $oob();
          } else {
            $oob();
          }
          const _tmp$5 = out.data;
          const _tmp$6 = dst + 1 | 0;
          const _tmp$7 = self.data;
          const _tmp$8 = src + 1 | 0;
          if (_tmp$6 >>> 0 < _tmp$5.length) {
            _tmp$5[_tmp$6] = _tmp$8 >>> 0 < _tmp$7.length ? _tmp$7[_tmp$8] : $oob();
          } else {
            $oob();
          }
          const _tmp$9 = out.data;
          const _tmp$10 = dst + 2 | 0;
          const _tmp$11 = self.data;
          const _tmp$12 = src + 2 | 0;
          if (_tmp$10 >>> 0 < _tmp$9.length) {
            _tmp$9[_tmp$10] = _tmp$12 >>> 0 < _tmp$11.length ? _tmp$11[_tmp$12] : $oob();
          } else {
            $oob();
          }
          const _tmp$13 = out.data;
          const _tmp$14 = dst + 3 | 0;
          const _tmp$15 = self.data;
          const _tmp$16 = src + 3 | 0;
          if (_tmp$14 >>> 0 < _tmp$13.length) {
            _tmp$13[_tmp$14] = _tmp$16 >>> 0 < _tmp$15.length ? _tmp$15[_tmp$16] : $oob();
          } else {
            $oob();
          }
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
function _M0FP270717lee10pixelforge7adler32(data, from, to) {
  let a = 1;
  let b = 0;
  let _tmp = from;
  while (true) {
    const i = _tmp;
    if (i < to) {
      const _tmp$2 = a;
      if (i < 0 || i >= data.len) {
        $panic();
      }
      const _p = data.buf[i];
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
function _M0MP270717lee10pixelforge5Image8map__rgb(self, transform) {
  const out = _M0MP270717lee10pixelforge5Image4copy(self);
  const n = _M0MP270717lee10pixelforge5Image12pixel__count(self);
  let _tmp = 0;
  while (true) {
    const p = _tmp;
    if (p < n) {
      const base = Math.imul(p, 4) | 0;
      const _tmp$2 = self.data;
      const r = base >>> 0 < _tmp$2.length ? _tmp$2[base] : $oob();
      const _tmp$3 = self.data;
      const _tmp$4 = base + 1 | 0;
      const g = _tmp$4 >>> 0 < _tmp$3.length ? _tmp$3[_tmp$4] : $oob();
      const _tmp$5 = self.data;
      const _tmp$6 = base + 2 | 0;
      const b = _tmp$6 >>> 0 < _tmp$5.length ? _tmp$5[_tmp$6] : $oob();
      const _bind = transform(r, g, b);
      const _nr = _bind._0;
      const _ng = _bind._1;
      const _nb = _bind._2;
      const _tmp$7 = out.data;
      if (base >>> 0 < _tmp$7.length) {
        _tmp$7[base] = _nr < 0 ? 0 : _nr > 255 ? 255 : _nr & 255;
      } else {
        $oob();
      }
      const _tmp$8 = out.data;
      const _tmp$9 = base + 1 | 0;
      if (_tmp$9 >>> 0 < _tmp$8.length) {
        _tmp$8[_tmp$9] = _ng < 0 ? 0 : _ng > 255 ? 255 : _ng & 255;
      } else {
        $oob();
      }
      const _tmp$10 = out.data;
      const _tmp$11 = base + 2 | 0;
      if (_tmp$11 >>> 0 < _tmp$10.length) {
        _tmp$10[_tmp$11] = _nb < 0 ? 0 : _nb > 255 ? 255 : _nb & 255;
      } else {
        $oob();
      }
      _tmp = p + 1 | 0;
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
      if (i < 0 || i >= data.len) {
        $panic();
      }
      const _p = data.buf[i];
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
  _M0FP270717lee10pixelforge13push__u32__be(out, payload.len);
  const crc_start = out.len;
  const _bind = ctype.len;
  const _bind$2 = ctype.buf;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const t = _bind$2[_];
      _M0FP270717lee10pixelforge8push__u8(out, t);
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const _bind$3 = payload.len;
  const _bind$4 = payload.buf;
  let _tmp$2 = 0;
  while (true) {
    const _ = _tmp$2;
    if (_ < _bind$3) {
      const b = _bind$4[_];
      _M0MPC15array5Array4pushGyE(out, b);
      _tmp$2 = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  _M0FP270717lee10pixelforge14push__uint__be(out, _M0FP270717lee10pixelforge5crc32(out, crc_start, out.len));
}
function _M0FP270717lee10pixelforge13reverse__bits(code, n) {
  let value = 0;
  let remaining = code;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < n) {
      value = value << 1 | remaining & 1;
      remaining = remaining >> 1;
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return value;
}
function _M0FP270717lee10pixelforge11fixed__code(symbol) {
  return symbol <= 143 ? { _0: _M0FP270717lee10pixelforge13reverse__bits(48 + symbol | 0, 8), _1: 8 } : symbol <= 255 ? { _0: _M0FP270717lee10pixelforge13reverse__bits((400 + symbol | 0) - 144 | 0, 9), _1: 9 } : symbol <= 279 ? { _0: _M0FP270717lee10pixelforge13reverse__bits(symbol - 256 | 0, 7), _1: 7 } : { _0: _M0FP270717lee10pixelforge13reverse__bits((192 + symbol | 0) - 280 | 0, 8), _1: 8 };
}
function _M0FP270717lee10pixelforge17fixed__dist__code(symbol) {
  return { _0: _M0FP270717lee10pixelforge13reverse__bits(symbol, 5), _1: 5 };
}
function _M0MP270717lee10pixelforge9BitWriter5write(self, value, count) {
  let remaining = value;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < count) {
      self.current = self.current | (remaining & 1) << self.bits;
      self.bits = self.bits + 1 | 0;
      remaining = remaining >> 1;
      if (self.bits === 8) {
        _M0MPC15array5Array4pushGyE(self.out, self.current & 255);
        self.current = 0;
        self.bits = 0;
      }
      _tmp = _ + 1 | 0;
      continue;
    } else {
      return;
    }
  }
}
function _M0MP270717lee10pixelforge9BitWriter6finish(self) {
  if (self.bits > 0) {
    _M0MPC15array5Array4pushGyE(self.out, self.current & 255);
    self.current = 0;
    self.bits = 0;
    return;
  } else {
    return;
  }
}
function _M0FP270717lee10pixelforge14deflate__fixed(raw) {
  const writer = new _M0TP270717lee10pixelforge9BitWriter(new _M0TPB5ArrayGyE(new Uint8Array([]), 0), 0, 0);
  _M0MP270717lee10pixelforge9BitWriter5write(writer, 1, 1);
  _M0MP270717lee10pixelforge9BitWriter5write(writer, 1, 2);
  let length_base_buf = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258];
  let length_base_len = 29;
  let length_extra_buf = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0];
  let length_extra_len = 29;
  let pos = 0;
  while (true) {
    if (pos < raw.len) {
      let run = 1;
      while (true) {
        let _tmp;
        if ((pos + run | 0) < raw.len) {
          let _tmp$2;
          if (run < 258) {
            const _bind = pos + run | 0;
            if (_bind < 0 || _bind >= raw.len) {
              $panic();
            }
            const _tmp$3 = raw.buf[_bind];
            const _bind$2 = pos;
            if (_bind$2 < 0 || _bind$2 >= raw.len) {
              $panic();
            }
            _tmp$2 = _tmp$3 === raw.buf[_bind$2];
          } else {
            _tmp$2 = false;
          }
          _tmp = _tmp$2;
        } else {
          _tmp = false;
        }
        if (_tmp) {
          run = run + 1 | 0;
          continue;
        } else {
          break;
        }
      }
      let _tmp;
      if (pos > 0) {
        let _tmp$2;
        if (run >= 3) {
          const _bind = pos - 1 | 0;
          if (_bind < 0 || _bind >= raw.len) {
            $panic();
          }
          const _tmp$3 = raw.buf[_bind];
          const _bind$2 = pos;
          if (_bind$2 < 0 || _bind$2 >= raw.len) {
            $panic();
          }
          _tmp$2 = _tmp$3 === raw.buf[_bind$2];
        } else {
          _tmp$2 = false;
        }
        _tmp = _tmp$2;
      } else {
        _tmp = false;
      }
      if (_tmp) {
        let index = 0;
        while (true) {
          let _tmp$2;
          if (index < 28) {
            const _tmp$3 = run;
            const _bind = index;
            if (_bind < 0 || _bind >= length_base_len) {
              $panic();
            }
            const _tmp$4 = length_base_buf[_bind];
            const _bind$2 = index;
            if (_bind$2 < 0 || _bind$2 >= length_extra_len) {
              $panic();
            }
            _tmp$2 = _tmp$3 > (_tmp$4 + ((1 << length_extra_buf[_bind$2]) - 1 | 0) | 0);
          } else {
            _tmp$2 = false;
          }
          if (_tmp$2) {
            index = index + 1 | 0;
            continue;
          } else {
            break;
          }
        }
        const _bind = _M0FP270717lee10pixelforge11fixed__code(257 + index | 0);
        const _code = _bind._0;
        const _bits = _bind._1;
        _M0MP270717lee10pixelforge9BitWriter5write(writer, _code, _bits);
        const _tmp$2 = run;
        const _bind$2 = index;
        if (_bind$2 < 0 || _bind$2 >= length_base_len) {
          $panic();
        }
        const _tmp$3 = _tmp$2 - length_base_buf[_bind$2] | 0;
        const _bind$3 = index;
        if (_bind$3 < 0 || _bind$3 >= length_extra_len) {
          $panic();
        }
        _M0MP270717lee10pixelforge9BitWriter5write(writer, _tmp$3, length_extra_buf[_bind$3]);
        const _bind$4 = _M0FP270717lee10pixelforge17fixed__dist__code(0);
        const _distance_code = _bind$4._0;
        const _distance_bits = _bind$4._1;
        _M0MP270717lee10pixelforge9BitWriter5write(writer, _distance_code, _distance_bits);
        pos = pos + run | 0;
      } else {
        const _bind = pos;
        if (_bind < 0 || _bind >= raw.len) {
          $panic();
        }
        const _bind$2 = _M0FP270717lee10pixelforge11fixed__code(raw.buf[_bind]);
        const _code = _bind$2._0;
        const _bits = _bind$2._1;
        _M0MP270717lee10pixelforge9BitWriter5write(writer, _code, _bits);
        pos = pos + 1 | 0;
      }
      continue;
    } else {
      break;
    }
  }
  const _bind = _M0FP270717lee10pixelforge11fixed__code(256);
  const _end_code = _bind._0;
  const _end_bits = _bind._1;
  _M0MP270717lee10pixelforge9BitWriter5write(writer, _end_code, _end_bits);
  _M0MP270717lee10pixelforge9BitWriter6finish(writer);
  return writer.out;
}
function _M0FP270717lee10pixelforge5paeth(a, b, c) {
  const p = (a + b | 0) - c | 0;
  const _p = p - a | 0;
  const pa = _p < 0 ? -_p | 0 : _p;
  const _p$2 = p - b | 0;
  const pb = _p$2 < 0 ? -_p$2 | 0 : _p$2;
  const _p$3 = p - c | 0;
  const pc = _p$3 < 0 ? -_p$3 | 0 : _p$3;
  return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
}
function _M0FP270717lee10pixelforge11png__encode(img) {
  const out = new _M0TPB5ArrayGyE(new Uint8Array([]), 0);
  let _bind_buf = [137, 80, 78, 71, 13, 10, 26, 10];
  let _bind_len = 8;
  const _bind = _bind_len;
  const _bind$2 = _bind_buf;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const s = _bind$2[_];
      _M0FP270717lee10pixelforge8push__u8(out, s);
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const ihdr = new _M0TPB5ArrayGyE(new Uint8Array([]), 0);
  _M0FP270717lee10pixelforge13push__u32__be(ihdr, img.width);
  _M0FP270717lee10pixelforge13push__u32__be(ihdr, img.height);
  let _bind_buf$2 = [8, 6, 0, 0, 0];
  let _bind_len$2 = 5;
  const _bind$3 = _bind_len$2;
  const _bind$4 = _bind_buf$2;
  let _tmp$2 = 0;
  while (true) {
    const _ = _tmp$2;
    if (_ < _bind$3) {
      const v = _bind$4[_];
      _M0FP270717lee10pixelforge8push__u8(ihdr, v);
      _tmp$2 = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  _M0FP270717lee10pixelforge11push__chunk(out, new _M0TPB5ArrayGiE([73, 72, 68, 82], 4), ihdr);
  const raw = new _M0TPB5ArrayGyE(new Uint8Array([]), 0);
  const stride = Math.imul(img.width, 4) | 0;
  const prev = _M0MPC15array5Array4makeGiE(stride, 0);
  const cur = _M0MPC15array5Array4makeGiE(stride, 0);
  const _bind$5 = img.height;
  let _tmp$3 = 0;
  while (true) {
    const y = _tmp$3;
    if (y < _bind$5) {
      let best_filter = 0;
      let best_score = -1;
      let _tmp$4 = 0;
      while (true) {
        const filter = _tmp$4;
        if (filter < 5) {
          let score = 0;
          let _tmp$5 = 0;
          while (true) {
            const i = _tmp$5;
            if (i < stride) {
              const _tmp$6 = img.data;
              const _tmp$7 = (Math.imul(y, stride) | 0) + i | 0;
              const x = _tmp$7 >>> 0 < _tmp$6.length ? _tmp$6[_tmp$7] : $oob();
              let a;
              if (i >= 4) {
                const _tmp$8 = img.data;
                const _tmp$9 = ((Math.imul(y, stride) | 0) + i | 0) - 4 | 0;
                a = _tmp$9 >>> 0 < _tmp$8.length ? _tmp$8[_tmp$9] : $oob();
              } else {
                a = 0;
              }
              if (i < 0 || i >= prev.len) {
                $panic();
              }
              const b = prev.buf[i];
              let c;
              if (i >= 4) {
                const _bind$6 = i - 4 | 0;
                if (_bind$6 < 0 || _bind$6 >= prev.len) {
                  $panic();
                }
                c = prev.buf[_bind$6];
              } else {
                c = 0;
              }
              let pred;
              switch (filter) {
                case 0: {
                  pred = 0;
                  break;
                }
                case 1: {
                  pred = a;
                  break;
                }
                case 2: {
                  pred = b;
                  break;
                }
                case 3: {
                  pred = (a + b | 0) / 2 | 0;
                  break;
                }
                default: {
                  pred = _M0FP270717lee10pixelforge5paeth(a, b, c);
                }
              }
              const d = (((x - pred | 0) % 256 | 0) + 256 | 0) % 256 | 0;
              const signed = d > 127 ? d - 256 | 0 : d;
              score = score + (signed < 0 ? -signed | 0 : signed) | 0;
              _tmp$5 = i + 1 | 0;
              continue;
            } else {
              break;
            }
          }
          if (best_score < 0 || score < best_score) {
            best_score = score;
            best_filter = filter;
          }
          _tmp$4 = filter + 1 | 0;
          continue;
        } else {
          break;
        }
      }
      _M0MPC15array5Array4pushGyE(raw, best_filter & 255);
      let _tmp$5 = 0;
      while (true) {
        const i = _tmp$5;
        if (i < stride) {
          const _tmp$6 = img.data;
          const _tmp$7 = (Math.imul(y, stride) | 0) + i | 0;
          const x = _tmp$7 >>> 0 < _tmp$6.length ? _tmp$6[_tmp$7] : $oob();
          let a;
          if (i >= 4) {
            const _tmp$8 = img.data;
            const _tmp$9 = ((Math.imul(y, stride) | 0) + i | 0) - 4 | 0;
            a = _tmp$9 >>> 0 < _tmp$8.length ? _tmp$8[_tmp$9] : $oob();
          } else {
            a = 0;
          }
          if (i < 0 || i >= prev.len) {
            $panic();
          }
          const b = prev.buf[i];
          let c;
          if (i >= 4) {
            const _bind$6 = i - 4 | 0;
            if (_bind$6 < 0 || _bind$6 >= prev.len) {
              $panic();
            }
            c = prev.buf[_bind$6];
          } else {
            c = 0;
          }
          const _bind$6 = best_filter;
          let pred;
          switch (_bind$6) {
            case 0: {
              pred = 0;
              break;
            }
            case 1: {
              pred = a;
              break;
            }
            case 2: {
              pred = b;
              break;
            }
            case 3: {
              pred = (a + b | 0) / 2 | 0;
              break;
            }
            default: {
              pred = _M0FP270717lee10pixelforge5paeth(a, b, c);
            }
          }
          _M0MPC15array5Array4pushGyE(raw, ((((x - pred | 0) % 256 | 0) + 256 | 0) % 256 | 0) & 255);
          if (i < 0 || i >= cur.len) {
            $panic();
          }
          cur.buf[i] = x;
          _tmp$5 = i + 1 | 0;
          continue;
        } else {
          break;
        }
      }
      let _tmp$6 = 0;
      while (true) {
        const i = _tmp$6;
        if (i < stride) {
          if (i < 0 || i >= cur.len) {
            $panic();
          }
          const _bind$6 = cur.buf[i];
          if (i < 0 || i >= prev.len) {
            $panic();
          }
          prev.buf[i] = _bind$6;
          _tmp$6 = i + 1 | 0;
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
  const idat = new _M0TPB5ArrayGyE(new Uint8Array([]), 0);
  _M0MPC15array5Array4pushGyE(idat, 120);
  _M0MPC15array5Array4pushGyE(idat, 156);
  const _bind$6 = _M0FP270717lee10pixelforge14deflate__fixed(raw);
  const _bind$7 = _bind$6.len;
  const _bind$8 = _bind$6.buf;
  let _tmp$4 = 0;
  while (true) {
    const _ = _tmp$4;
    if (_ < _bind$7) {
      const b = _bind$8[_];
      _M0MPC15array5Array4pushGyE(idat, b);
      _tmp$4 = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  _M0FP270717lee10pixelforge14push__uint__be(idat, _M0FP270717lee10pixelforge7adler32(raw, 0, raw.len));
  _M0FP270717lee10pixelforge11push__chunk(out, new _M0TPB5ArrayGiE([73, 68, 65, 84], 4), idat);
  _M0FP270717lee10pixelforge11push__chunk(out, new _M0TPB5ArrayGiE([73, 69, 78, 68], 4), new _M0TPB5ArrayGyE(new Uint8Array([]), 0));
  return out;
}
function _M0MP270717lee10pixelforge6Kernel3new(size, weights, divisor, bias) {
  if (size <= 0 || (size % 2 | 0) === 0) {
    $panic("Kernel::new: size must be a positive odd number");
  }
  if (BigInt.asUintN(64, BigInt.asUintN(64, BigInt.asUintN(64, BigInt(size)) * BigInt.asUintN(64, BigInt(size)))) !== BigInt.asUintN(64, BigInt.asUintN(64, BigInt(weights.len)))) {
    $panic("Kernel::new: weights length must equal size * size");
  }
  if (divisor === 0 || (divisor !== divisor || (divisor > _M0FPB18double__max__value || divisor < _M0FPB18double__min__value || (bias !== bias || (bias > _M0FPB18double__max__value || bias < _M0FPB18double__min__value))))) {
    $panic("Kernel::new: normalization must be finite and divisor nonzero");
  }
  const _bind = weights.len;
  const _bind$2 = weights.buf;
  let _tmp = 0;
  while (true) {
    const _ = _tmp;
    if (_ < _bind) {
      const weight = _bind$2[_];
      if (weight !== weight || (weight > _M0FPB18double__max__value || weight < _M0FPB18double__min__value)) {
        $panic("Kernel::new: weights must be finite");
      }
      _tmp = _ + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return new _M0TP270717lee10pixelforge6Kernel(size, weights, divisor, bias);
}
function _M0MP270717lee10pixelforge5Image8convolve(self, kernel) {
  _M0MP270717lee10pixelforge6Kernel3new(kernel.size, kernel.weights, kernel.divisor, kernel.bias);
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
                  const _bind$5 = kernel.weights;
                  const _bind$6 = (Math.imul(ky, kernel.size) | 0) + kx | 0;
                  if (_bind$6 < 0 || _bind$6 >= _bind$5.len) {
                    $panic();
                  }
                  const w = _bind$5.buf[_bind$6];
                  const base = Math.imul((Math.imul(sy, self.width) | 0) + sx | 0, 4) | 0;
                  const _tmp$5 = sum_r;
                  const _tmp$6 = self.data;
                  sum_r = _tmp$5 + ((base >>> 0 < _tmp$6.length ? _tmp$6[base] : $oob()) + 0) * w;
                  const _tmp$7 = sum_g;
                  const _tmp$8 = self.data;
                  const _tmp$9 = base + 1 | 0;
                  sum_g = _tmp$7 + ((_tmp$9 >>> 0 < _tmp$8.length ? _tmp$8[_tmp$9] : $oob()) + 0) * w;
                  const _tmp$10 = sum_b;
                  const _tmp$11 = self.data;
                  const _tmp$12 = base + 2 | 0;
                  sum_b = _tmp$10 + ((_tmp$12 >>> 0 < _tmp$11.length ? _tmp$11[_tmp$12] : $oob()) + 0) * w;
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
          if (base >>> 0 < _tmp$4.length) {
            _tmp$4[base] = _p < 0 ? 0 : _p > 255 ? 255 : _p & 255;
          } else {
            $oob();
          }
          const _tmp$5 = out.data;
          const _tmp$6 = base + 1 | 0;
          const _p$2 = _M0MPC16double6Double7to__int(sum_g / kernel.divisor + kernel.bias);
          if (_tmp$6 >>> 0 < _tmp$5.length) {
            _tmp$5[_tmp$6] = _p$2 < 0 ? 0 : _p$2 > 255 ? 255 : _p$2 & 255;
          } else {
            $oob();
          }
          const _tmp$7 = out.data;
          const _tmp$8 = base + 2 | 0;
          const _p$3 = _M0MPC16double6Double7to__int(sum_b / kernel.divisor + kernel.bias);
          if (_tmp$8 >>> 0 < _tmp$7.length) {
            _tmp$7[_tmp$8] = _p$3 < 0 ? 0 : _p$3 > 255 ? 255 : _p$3 & 255;
          } else {
            $oob();
          }
          const _tmp$9 = out.data;
          const _tmp$10 = base + 3 | 0;
          const _tmp$11 = self.data;
          const _tmp$12 = base + 3 | 0;
          if (_tmp$10 >>> 0 < _tmp$9.length) {
            _tmp$9[_tmp$10] = _tmp$12 >>> 0 < _tmp$11.length ? _tmp$11[_tmp$12] : $oob();
          } else {
            $oob();
          }
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
function _M0MP270717lee10pixelforge6Kernel14gaussian__blur() {
  return _M0MP270717lee10pixelforge6Kernel3new(3, new _M0TPB5ArrayGdE([1, 2, 1, 2, 4, 2, 1, 2, 1], 9), 16, 0);
}
function _M0MP270717lee10pixelforge5Image4blur(self) {
  return _M0MP270717lee10pixelforge5Image8convolve(self, _M0MP270717lee10pixelforge6Kernel14gaussian__blur());
}
function _M0MP270717lee10pixelforge5Image10brightness(self, delta) {
  return _M0MP270717lee10pixelforge5Image8map__rgb(self, (r, g, b) => ({ _0: r + delta | 0, _1: g + delta | 0, _2: b + delta | 0 }));
}
function _M0MP270717lee10pixelforge5Image9grayscale(self) {
  return _M0MP270717lee10pixelforge5Image8map__rgb(self, (r, g, b) => {
    const y = (((Math.imul(299, r) | 0) + (Math.imul(587, g) | 0) | 0) + (Math.imul(114, b) | 0) | 0) / 1000 | 0;
    return { _0: y, _1: y, _2: y };
  });
}
function _M0MP270717lee10pixelforge5Image5canny(self, low, high) {
  const w = self.width;
  const h = self.height;
  const n = Math.imul(w, h) | 0;
  const gray = _M0MP270717lee10pixelforge5Image4blur(_M0MP270717lee10pixelforge5Image9grayscale(self));
  const gx = _M0MPC15array5Array4makeGiE(n, 0);
  const gy = _M0MPC15array5Array4makeGiE(n, 0);
  const mag = _M0MPC15array5Array4makeGiE(n, 0);
  let kx_buf = [-1, 0, 1, -2, 0, 2, -1, 0, 1];
  let kx_len = 9;
  let ky_buf = [-1, -2, -1, 0, 0, 0, 1, 2, 1];
  let ky_len = 9;
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
                  const lum = _tmp$6 >>> 0 < _tmp$5.length ? _tmp$5[_tmp$6] : $oob();
                  const _tmp$7 = sx;
                  const _bind = (Math.imul(j, 3) | 0) + i | 0;
                  if (_bind < 0 || _bind >= kx_len) {
                    $panic();
                  }
                  sx = _tmp$7 + (Math.imul(lum, kx_buf[_bind]) | 0) | 0;
                  const _tmp$8 = sy;
                  const _bind$2 = (Math.imul(j, 3) | 0) + i | 0;
                  if (_bind$2 < 0 || _bind$2 >= ky_len) {
                    $panic();
                  }
                  sy = _tmp$8 + (Math.imul(lum, ky_buf[_bind$2]) | 0) | 0;
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
          const _bind = sx;
          if (p < 0 || p >= gx.len) {
            $panic();
          }
          gx.buf[p] = _bind;
          const _bind$2 = sy;
          if (p < 0 || p >= gy.len) {
            $panic();
          }
          gy.buf[p] = _bind$2;
          const _p = sx;
          const _tmp$4 = _p < 0 ? -_p | 0 : _p;
          const _p$2 = sy;
          const _bind$3 = _tmp$4 + (_p$2 < 0 ? -_p$2 | 0 : _p$2) | 0;
          if (p < 0 || p >= mag.len) {
            $panic();
          }
          mag.buf[p] = _bind$3;
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
            if (p < 0 || p >= mag.len) {
              $panic();
            }
            const m = mag.buf[p];
            if (m === 0) {
              break _L;
            }
            if (p < 0 || p >= gx.len) {
              $panic();
            }
            const _p = gx.buf[p];
            const ax = (_p < 0 ? -_p | 0 : _p) + 0;
            if (p < 0 || p >= gy.len) {
              $panic();
            }
            const _p$2 = gy.buf[p];
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
                if (p < 0 || p >= gx.len) {
                  $panic();
                }
                const _tmp$4 = gx.buf[p];
                if (p < 0 || p >= gy.len) {
                  $panic();
                }
                if ((Math.imul(_tmp$4, gy.buf[p]) | 0) > 0) {
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
            let _tmp$6;
            if (q1 < 0 || q1 >= mag.len) {
              $panic();
            }
            if (m >= mag.buf[q1]) {
              if (q2 < 0 || q2 >= mag.len) {
                $panic();
              }
              _tmp$6 = m >= mag.buf[q2];
            } else {
              _tmp$6 = false;
            }
            if (_tmp$6) {
              if (p < 0 || p >= thin.len) {
                $panic();
              }
              thin.buf[p] = m;
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
  const stack = new _M0TPB5ArrayGiE([], 0);
  let _tmp$3 = 0;
  while (true) {
    const p = _tmp$3;
    if (p < n) {
      if (p < 0 || p >= thin.len) {
        $panic();
      }
      if (thin.buf[p] >= high) {
        if (p < 0 || p >= state.len) {
          $panic();
        }
        state.buf[p] = 2;
        _M0MPC15array5Array4pushGiE(stack, p);
      } else {
        if (p < 0 || p >= thin.len) {
          $panic();
        }
        if (thin.buf[p] >= low) {
          if (p < 0 || p >= state.len) {
            $panic();
          }
          state.buf[p] = 1;
        }
      }
      _tmp$3 = p + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  while (true) {
    if (stack.len > 0) {
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
                if (q < 0 || q >= state.len) {
                  $panic();
                }
                if (state.buf[q] === 1) {
                  if (q < 0 || q >= state.len) {
                    $panic();
                  }
                  state.buf[q] = 2;
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
      let v;
      if (p < 0 || p >= state.len) {
        $panic();
      }
      if (state.buf[p] === 2) {
        v = 255;
      } else {
        v = 0;
      }
      const base = Math.imul(p, 4) | 0;
      const _tmp$5 = out.data;
      if (base >>> 0 < _tmp$5.length) {
        _tmp$5[base] = v;
      } else {
        $oob();
      }
      const _tmp$6 = out.data;
      const _tmp$7 = base + 1 | 0;
      if (_tmp$7 >>> 0 < _tmp$6.length) {
        _tmp$6[_tmp$7] = v;
      } else {
        $oob();
      }
      const _tmp$8 = out.data;
      const _tmp$9 = base + 2 | 0;
      if (_tmp$9 >>> 0 < _tmp$8.length) {
        _tmp$8[_tmp$9] = v;
      } else {
        $oob();
      }
      const _tmp$10 = out.data;
      const _tmp$11 = base + 3 | 0;
      const _tmp$12 = self.data;
      const _tmp$13 = base + 3 | 0;
      if (_tmp$11 >>> 0 < _tmp$10.length) {
        _tmp$10[_tmp$11] = _tmp$13 >>> 0 < _tmp$12.length ? _tmp$12[_tmp$13] : $oob();
      } else {
        $oob();
      }
      _tmp$4 = p + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return out;
}
function _M0MP270717lee10pixelforge5Image8contrastN5applyS507(factor, c) {
  return _M0MPC16double6Double7to__int((c + 0 - 128) * factor + 128);
}
function _M0MP270717lee10pixelforge5Image8contrast(self, factor) {
  return _M0MP270717lee10pixelforge5Image8map__rgb(self, (r, g, b) => ({ _0: _M0MP270717lee10pixelforge5Image8contrastN5applyS507(factor, r), _1: _M0MP270717lee10pixelforge5Image8contrastN5applyS507(factor, g), _2: _M0MP270717lee10pixelforge5Image8contrastN5applyS507(factor, b) }));
}
function _M0FP270717lee10pixelforge7diffuse(buf, w, h, x, y, err) {
  if ((x + 1 | 0) < w) {
    const _bind = ((Math.imul(y, w) | 0) + x | 0) + 1 | 0;
    const _bind$2 = ((Math.imul(y, w) | 0) + x | 0) + 1 | 0;
    if (_bind$2 < 0 || _bind$2 >= buf.len) {
      $panic();
    }
    const _bind$3 = buf.buf[_bind$2] + ((Math.imul(err, 7) | 0) / 16 | 0) | 0;
    if (_bind < 0 || _bind >= buf.len) {
      $panic();
    }
    buf.buf[_bind] = _bind$3;
  }
  if ((y + 1 | 0) < h) {
    if (x > 0) {
      const _bind = ((Math.imul(y + 1 | 0, w) | 0) + x | 0) - 1 | 0;
      const _bind$2 = ((Math.imul(y + 1 | 0, w) | 0) + x | 0) - 1 | 0;
      if (_bind$2 < 0 || _bind$2 >= buf.len) {
        $panic();
      }
      const _bind$3 = buf.buf[_bind$2] + ((Math.imul(err, 3) | 0) / 16 | 0) | 0;
      if (_bind < 0 || _bind >= buf.len) {
        $panic();
      }
      buf.buf[_bind] = _bind$3;
    }
    const _bind = (Math.imul(y + 1 | 0, w) | 0) + x | 0;
    const _bind$2 = (Math.imul(y + 1 | 0, w) | 0) + x | 0;
    if (_bind$2 < 0 || _bind$2 >= buf.len) {
      $panic();
    }
    const _bind$3 = buf.buf[_bind$2] + ((Math.imul(err, 5) | 0) / 16 | 0) | 0;
    if (_bind < 0 || _bind >= buf.len) {
      $panic();
    }
    buf.buf[_bind] = _bind$3;
    if ((x + 1 | 0) < w) {
      const _bind$4 = ((Math.imul(y + 1 | 0, w) | 0) + x | 0) + 1 | 0;
      const _bind$5 = ((Math.imul(y + 1 | 0, w) | 0) + x | 0) + 1 | 0;
      if (_bind$5 < 0 || _bind$5 >= buf.len) {
        $panic();
      }
      const _bind$6 = buf.buf[_bind$5] + ((Math.imul(err, 1) | 0) / 16 | 0) | 0;
      if (_bind$4 < 0 || _bind$4 >= buf.len) {
        $panic();
      }
      buf.buf[_bind$4] = _bind$6;
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
      const _tmp$3 = Math.imul(299, base >>> 0 < _tmp$2.length ? _tmp$2[base] : $oob()) | 0;
      const _tmp$4 = self.data;
      const _tmp$5 = base + 1 | 0;
      const _tmp$6 = _tmp$3 + (Math.imul(587, _tmp$5 >>> 0 < _tmp$4.length ? _tmp$4[_tmp$5] : $oob()) | 0) | 0;
      const _tmp$7 = self.data;
      const _tmp$8 = base + 2 | 0;
      const _bind$2 = (_tmp$6 + (Math.imul(114, _tmp$8 >>> 0 < _tmp$7.length ? _tmp$7[_tmp$8] : $oob()) | 0) | 0) / 1000 | 0;
      if (p < 0 || p >= buf.len) {
        $panic();
      }
      buf.buf[p] = _bind$2;
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
          const _bind$2 = (Math.imul(y, w) | 0) + x | 0;
          if (_bind$2 < 0 || _bind$2 >= buf.len) {
            $panic();
          }
          const old = buf.buf[_bind$2];
          const newv = _M0FP270717lee10pixelforge8quantize(old, l);
          _M0FP270717lee10pixelforge7diffuse(buf, w, h, x, y, old - newv | 0);
          const b = newv < 0 ? 0 : newv > 255 ? 255 : newv & 255;
          const base = Math.imul((Math.imul(y, w) | 0) + x | 0, 4) | 0;
          const _tmp$4 = out.data;
          if (base >>> 0 < _tmp$4.length) {
            _tmp$4[base] = b;
          } else {
            $oob();
          }
          const _tmp$5 = out.data;
          const _tmp$6 = base + 1 | 0;
          if (_tmp$6 >>> 0 < _tmp$5.length) {
            _tmp$5[_tmp$6] = b;
          } else {
            $oob();
          }
          const _tmp$7 = out.data;
          const _tmp$8 = base + 2 | 0;
          if (_tmp$8 >>> 0 < _tmp$7.length) {
            _tmp$7[_tmp$8] = b;
          } else {
            $oob();
          }
          const _tmp$9 = out.data;
          const _tmp$10 = base + 3 | 0;
          const _tmp$11 = self.data;
          const _tmp$12 = base + 3 | 0;
          if (_tmp$10 >>> 0 < _tmp$9.length) {
            _tmp$9[_tmp$10] = _tmp$12 >>> 0 < _tmp$11.length ? _tmp$11[_tmp$12] : $oob();
          } else {
            $oob();
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
  return out;
}
function _M0MP270717lee10pixelforge5Image12dither__mono(self) {
  return _M0MP270717lee10pixelforge5Image17dither__grayscale(self, 2);
}
function _M0MP270717lee10pixelforge6Kernel5edges() {
  return _M0MP270717lee10pixelforge6Kernel3new(3, new _M0TPB5ArrayGdE([-1, -1, -1, -1, 8, -1, -1, -1, -1], 9), 1, 0);
}
function _M0MP270717lee10pixelforge5Image5edges(self) {
  return _M0MP270717lee10pixelforge5Image8convolve(self, _M0MP270717lee10pixelforge6Kernel5edges());
}
function _M0MP270717lee10pixelforge6Kernel6emboss() {
  return _M0MP270717lee10pixelforge6Kernel3new(3, new _M0TPB5ArrayGdE([-2, -1, 0, -1, 1, 1, 0, 1, 2], 9), 1, 128);
}
function _M0MP270717lee10pixelforge5Image6emboss(self) {
  return _M0MP270717lee10pixelforge5Image8convolve(self, _M0MP270717lee10pixelforge6Kernel6emboss());
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
      if (i >>> 0 < lut.length) {
        lut[i] = _M0MPC16double6Double7to__int(_M0FPC14math3pow(normalized, inv) * 255 + 0.5);
      } else {
        $oob();
      }
      _tmp = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return _M0MP270717lee10pixelforge5Image8map__rgb(self, (r, g$2, b) => ({ _0: r >>> 0 < lut.length ? lut[r] : $oob(), _1: g$2 >>> 0 < lut.length ? lut[g$2] : $oob(), _2: b >>> 0 < lut.length ? lut[b] : $oob() }));
}
function _M0MP270717lee10pixelforge5Image19histogram__equalize(self) {
  const n = _M0MP270717lee10pixelforge5Image12pixel__count(self);
  const hist = $make_array_len_and_init(256, 0);
  let _tmp = 0;
  while (true) {
    const p = _tmp;
    if (p < n) {
      const base = Math.imul(p, 4) | 0;
      const _tmp$2 = self.data;
      const _tmp$3 = Math.imul(299, base >>> 0 < _tmp$2.length ? _tmp$2[base] : $oob()) | 0;
      const _tmp$4 = self.data;
      const _tmp$5 = base + 1 | 0;
      const _tmp$6 = _tmp$3 + (Math.imul(587, _tmp$5 >>> 0 < _tmp$4.length ? _tmp$4[_tmp$5] : $oob()) | 0) | 0;
      const _tmp$7 = self.data;
      const _tmp$8 = base + 2 | 0;
      const y = (_tmp$6 + (Math.imul(114, _tmp$8 >>> 0 < _tmp$7.length ? _tmp$7[_tmp$8] : $oob()) | 0) | 0) / 1000 | 0;
      if (y >>> 0 < hist.length) {
        hist[y] = (y >>> 0 < hist.length ? hist[y] : $oob()) + 1 | 0;
      } else {
        $oob();
      }
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
      acc = acc + (i >>> 0 < hist.length ? hist[i] : $oob()) | 0;
      if (i >>> 0 < cdf.length) {
        cdf[i] = acc;
      } else {
        $oob();
      }
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
      if ((i >>> 0 < cdf.length ? cdf[i] : $oob()) !== 0) {
        cdf_min = i >>> 0 < cdf.length ? cdf[i] : $oob();
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
        const _tmp$6 = BigInt.asUintN(64, BigInt(denom));
        if (_tmp$6 === 0n) {
          $panic();
        }
        _tmp$5 = Number(BigInt.asIntN(32, BigInt.asUintN(64, BigInt.asIntN(64, BigInt.asUintN(64, BigInt.asUintN(64, BigInt((i >>> 0 < cdf.length ? cdf[i] : $oob()) - cdf_min | 0)) * 255n)) / BigInt.asIntN(64, _tmp$6)))) | 0;
      }
      if (i >>> 0 < lut.length) {
        lut[i] = _tmp$5;
      } else {
        $oob();
      }
      _tmp$4 = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return _M0MP270717lee10pixelforge5Image8map__rgb(self, (r, g, b) => {
    const y = (((Math.imul(299, r) | 0) + (Math.imul(587, g) | 0) | 0) + (Math.imul(114, b) | 0) | 0) / 1000 | 0;
    const e = y >>> 0 < lut.length ? lut[y] : $oob();
    return { _0: e, _1: e, _2: e };
  });
}
function _M0MP270717lee10pixelforge5Image6invert(self) {
  return _M0MP270717lee10pixelforge5Image8map__rgb(self, (r, g, b) => ({ _0: 255 - r | 0, _1: 255 - g | 0, _2: 255 - b | 0 }));
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
          if (_tmp$3 >>> 0 < vals.length) {
            vals[_tmp$3] = _tmp$5 >>> 0 < _tmp$4.length ? _tmp$4[_tmp$5] : $oob();
          } else {
            $oob();
          }
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
      const v = i >>> 0 < vals.length ? vals[i] : $oob();
      let j = i - 1 | 0;
      while (true) {
        let _tmp$3;
        if (j >= 0) {
          const _tmp$4 = j;
          _tmp$3 = (_tmp$4 >>> 0 < vals.length ? vals[_tmp$4] : $oob()) > v;
        } else {
          _tmp$3 = false;
        }
        if (_tmp$3) {
          const _tmp$4 = j + 1 | 0;
          const _tmp$5 = j;
          if (_tmp$4 >>> 0 < vals.length) {
            vals[_tmp$4] = _tmp$5 >>> 0 < vals.length ? vals[_tmp$5] : $oob();
          } else {
            $oob();
          }
          j = j - 1 | 0;
          continue;
        } else {
          break;
        }
      }
      const _tmp$3 = j + 1 | 0;
      if (_tmp$3 >>> 0 < vals.length) {
        vals[_tmp$3] = v;
      } else {
        $oob();
      }
      _tmp$2 = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  const _p = 4 >>> 0 < vals.length ? vals[4] : $oob();
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
          if (base >>> 0 < _tmp$3.length) {
            _tmp$3[base] = _M0FP270717lee10pixelforge15median__channel(self, x, y, 0);
          } else {
            $oob();
          }
          const _tmp$4 = out.data;
          const _tmp$5 = base + 1 | 0;
          if (_tmp$5 >>> 0 < _tmp$4.length) {
            _tmp$4[_tmp$5] = _M0FP270717lee10pixelforge15median__channel(self, x, y, 1);
          } else {
            $oob();
          }
          const _tmp$6 = out.data;
          const _tmp$7 = base + 2 | 0;
          if (_tmp$7 >>> 0 < _tmp$6.length) {
            _tmp$6[_tmp$7] = _M0FP270717lee10pixelforge15median__channel(self, x, y, 2);
          } else {
            $oob();
          }
          const _tmp$8 = out.data;
          const _tmp$9 = base + 3 | 0;
          const _tmp$10 = self.data;
          const _tmp$11 = base + 3 | 0;
          if (_tmp$9 >>> 0 < _tmp$8.length) {
            _tmp$8[_tmp$9] = _tmp$11 >>> 0 < _tmp$10.length ? _tmp$10[_tmp$11] : $oob();
          } else {
            $oob();
          }
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
function _M0MP270717lee10pixelforge5Image15luma__histogram(self) {
  const hist = $make_array_len_and_init(256, 0);
  const n = _M0MP270717lee10pixelforge5Image12pixel__count(self);
  let _tmp = 0;
  while (true) {
    const p = _tmp;
    if (p < n) {
      const base = Math.imul(p, 4) | 0;
      const _tmp$2 = self.data;
      const _tmp$3 = Math.imul(299, base >>> 0 < _tmp$2.length ? _tmp$2[base] : $oob()) | 0;
      const _tmp$4 = self.data;
      const _tmp$5 = base + 1 | 0;
      const _tmp$6 = _tmp$3 + (Math.imul(587, _tmp$5 >>> 0 < _tmp$4.length ? _tmp$4[_tmp$5] : $oob()) | 0) | 0;
      const _tmp$7 = self.data;
      const _tmp$8 = base + 2 | 0;
      const y = (_tmp$6 + (Math.imul(114, _tmp$8 >>> 0 < _tmp$7.length ? _tmp$7[_tmp$8] : $oob()) | 0) | 0) / 1000 | 0;
      if (y >>> 0 < hist.length) {
        hist[y] = (y >>> 0 < hist.length ? hist[y] : $oob()) + 1 | 0;
      } else {
        $oob();
      }
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
  const total = _M0MP270717lee10pixelforge5Image12pixel__count(self);
  if (total === 0) {
    return 0;
  }
  let sum_all = 0;
  let _tmp = 0;
  while (true) {
    const i = _tmp;
    if (i < 256) {
      sum_all = sum_all + ((Math.imul(i, i >>> 0 < hist.length ? hist[i] : $oob()) | 0) + 0);
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
        w_b = w_b + (t >>> 0 < hist.length ? hist[t] : $oob()) | 0;
        if (w_b === 0) {
          break _L;
        }
        const w_f = total - w_b | 0;
        if (w_f === 0) {
          break;
        }
        sum_b = sum_b + ((Math.imul(t, t >>> 0 < hist.length ? hist[t] : $oob()) | 0) + 0);
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
function _M0MP270717lee10pixelforge5Image4otsu(self) {
  const t = _M0MP270717lee10pixelforge5Image15otsu__threshold(self);
  return _M0MP270717lee10pixelforge5Image8map__rgb(self, (r, g, b) => {
    const y = (((Math.imul(299, r) | 0) + (Math.imul(587, g) | 0) | 0) + (Math.imul(114, b) | 0) | 0) / 1000 | 0;
    const v = y > t ? 255 : 0;
    return { _0: v, _1: v, _2: v };
  });
}
function _M0MP270717lee10pixelforge5Image8pixelate(self, block) {
  const size = block < 1 ? 1 : block;
  const out = _M0MP270717lee10pixelforge5Image3new(self.width, self.height);
  const blocks_y = self.height === 0 ? 0 : ((self.height - 1 | 0) / size | 0) + 1 | 0;
  const blocks_x = self.width === 0 ? 0 : ((self.width - 1 | 0) / size | 0) + 1 | 0;
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
          const _p = self.height - y0 | 0;
          const y1 = y0 + (size < _p ? size : _p) | 0;
          const _p$2 = self.width - x0 | 0;
          const x1 = x0 + (size < _p$2 ? size : _p$2) | 0;
          let sr = 0n;
          let sg = 0n;
          let sb = 0n;
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
                  sr = BigInt.asUintN(64, _tmp$5 + BigInt.asUintN(64, BigInt(base >>> 0 < _tmp$6.length ? _tmp$6[base] : $oob())));
                  const _tmp$7 = sg;
                  const _tmp$8 = self.data;
                  const _tmp$9 = base + 1 | 0;
                  sg = BigInt.asUintN(64, _tmp$7 + BigInt.asUintN(64, BigInt(_tmp$9 >>> 0 < _tmp$8.length ? _tmp$8[_tmp$9] : $oob())));
                  const _tmp$10 = sb;
                  const _tmp$11 = self.data;
                  const _tmp$12 = base + 2 | 0;
                  sb = BigInt.asUintN(64, _tmp$10 + BigInt.asUintN(64, BigInt(_tmp$12 >>> 0 < _tmp$11.length ? _tmp$11[_tmp$12] : $oob())));
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
          const _tmp$4 = BigInt.asUintN(64, BigInt(count));
          if (_tmp$4 === 0n) {
            $panic();
          }
          const _p$3 = Number(BigInt.asIntN(32, BigInt.asUintN(64, BigInt.asIntN(64, sr) / BigInt.asIntN(64, _tmp$4)))) | 0;
          const ar = _p$3 < 0 ? 0 : _p$3 > 255 ? 255 : _p$3 & 255;
          const _tmp$5 = BigInt.asUintN(64, BigInt(count));
          if (_tmp$5 === 0n) {
            $panic();
          }
          const _p$4 = Number(BigInt.asIntN(32, BigInt.asUintN(64, BigInt.asIntN(64, sg) / BigInt.asIntN(64, _tmp$5)))) | 0;
          const ag = _p$4 < 0 ? 0 : _p$4 > 255 ? 255 : _p$4 & 255;
          const _tmp$6 = BigInt.asUintN(64, BigInt(count));
          if (_tmp$6 === 0n) {
            $panic();
          }
          const _p$5 = Number(BigInt.asIntN(32, BigInt.asUintN(64, BigInt.asIntN(64, sb) / BigInt.asIntN(64, _tmp$6)))) | 0;
          const ab = _p$5 < 0 ? 0 : _p$5 > 255 ? 255 : _p$5 & 255;
          let _tmp$7 = y0;
          while (true) {
            const y = _tmp$7;
            if (y < y1) {
              let _tmp$8 = x0;
              while (true) {
                const x = _tmp$8;
                if (x < x1) {
                  const base = Math.imul((Math.imul(y, self.width) | 0) + x | 0, 4) | 0;
                  const _tmp$9 = out.data;
                  if (base >>> 0 < _tmp$9.length) {
                    _tmp$9[base] = ar;
                  } else {
                    $oob();
                  }
                  const _tmp$10 = out.data;
                  const _tmp$11 = base + 1 | 0;
                  if (_tmp$11 >>> 0 < _tmp$10.length) {
                    _tmp$10[_tmp$11] = ag;
                  } else {
                    $oob();
                  }
                  const _tmp$12 = out.data;
                  const _tmp$13 = base + 2 | 0;
                  if (_tmp$13 >>> 0 < _tmp$12.length) {
                    _tmp$12[_tmp$13] = ab;
                  } else {
                    $oob();
                  }
                  const _tmp$14 = out.data;
                  const _tmp$15 = base + 3 | 0;
                  const _tmp$16 = self.data;
                  const _tmp$17 = base + 3 | 0;
                  if (_tmp$15 >>> 0 < _tmp$14.length) {
                    _tmp$14[_tmp$15] = _tmp$17 >>> 0 < _tmp$16.length ? _tmp$16[_tmp$17] : $oob();
                  } else {
                    $oob();
                  }
                  _tmp$8 = x + 1 | 0;
                  continue;
                } else {
                  break;
                }
              }
              _tmp$7 = y + 1 | 0;
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
function _M0MP270717lee10pixelforge5Image9posterize(self, levels) {
  const l = levels < 2 ? 2 : levels > 256 ? 256 : levels;
  return _M0MP270717lee10pixelforge5Image8map__rgb(self, (r, g, b) => ({ _0: (Math.imul((Math.imul(r, l) | 0) / 256 | 0, 255) | 0) / (l - 1 | 0) | 0, _1: (Math.imul((Math.imul(g, l) | 0) / 256 | 0, 255) | 0) / (l - 1 | 0) | 0, _2: (Math.imul((Math.imul(b, l) | 0) / 256 | 0, 255) | 0) / (l - 1 | 0) | 0 }));
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
                  const lum = base >>> 0 < _tmp$5.length ? _tmp$5[base] : $oob();
                  const k = (Math.imul(ky, 3) | 0) + kx | 0;
                  const _tmp$6 = sx;
                  if (k < 0 || k >= gx.len) {
                    $panic();
                  }
                  sx = _tmp$6 + (Math.imul(lum, gx.buf[k]) | 0) | 0;
                  const _tmp$7 = sy;
                  if (k < 0 || k >= gy.len) {
                    $panic();
                  }
                  sy = _tmp$7 + (Math.imul(lum, gy.buf[k]) | 0) | 0;
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
          if (base >>> 0 < _tmp$5.length) {
            _tmp$5[base] = v;
          } else {
            $oob();
          }
          const _tmp$6 = out.data;
          const _tmp$7 = base + 1 | 0;
          if (_tmp$7 >>> 0 < _tmp$6.length) {
            _tmp$6[_tmp$7] = v;
          } else {
            $oob();
          }
          const _tmp$8 = out.data;
          const _tmp$9 = base + 2 | 0;
          if (_tmp$9 >>> 0 < _tmp$8.length) {
            _tmp$8[_tmp$9] = v;
          } else {
            $oob();
          }
          const _tmp$10 = out.data;
          const _tmp$11 = base + 3 | 0;
          const _tmp$12 = self.data;
          const _tmp$13 = base + 3 | 0;
          if (_tmp$11 >>> 0 < _tmp$10.length) {
            _tmp$10[_tmp$11] = _tmp$13 >>> 0 < _tmp$12.length ? _tmp$12[_tmp$13] : $oob();
          } else {
            $oob();
          }
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
  return _M0MP270717lee10pixelforge5Image15gradient__edges(self, new _M0TPB5ArrayGiE([-3, 0, 3, -10, 0, 10, -3, 0, 3], 9), new _M0TPB5ArrayGiE([-3, -10, -3, 0, 0, 0, 3, 10, 3], 9));
}
function _M0MP270717lee10pixelforge5Image5sepia(self) {
  return _M0MP270717lee10pixelforge5Image8map__rgb(self, (r, g, b) => {
    const nr = (((Math.imul(393, r) | 0) + (Math.imul(769, g) | 0) | 0) + (Math.imul(189, b) | 0) | 0) / 1000 | 0;
    const ng = (((Math.imul(349, r) | 0) + (Math.imul(686, g) | 0) | 0) + (Math.imul(168, b) | 0) | 0) / 1000 | 0;
    const nb = (((Math.imul(272, r) | 0) + (Math.imul(534, g) | 0) | 0) + (Math.imul(131, b) | 0) | 0) / 1000 | 0;
    return { _0: nr, _1: ng, _2: nb };
  });
}
function _M0MP270717lee10pixelforge6Kernel7sharpen() {
  return _M0MP270717lee10pixelforge6Kernel3new(3, new _M0TPB5ArrayGdE([0, -1, 0, -1, 5, -1, 0, -1, 0], 9), 1, 0);
}
function _M0MP270717lee10pixelforge5Image7sharpen(self) {
  return _M0MP270717lee10pixelforge5Image8convolve(self, _M0MP270717lee10pixelforge6Kernel7sharpen());
}
function _M0MP270717lee10pixelforge5Image5sobel(self) {
  return _M0MP270717lee10pixelforge5Image15gradient__edges(self, new _M0TPB5ArrayGiE([-1, 0, 1, -2, 0, 2, -1, 0, 1], 9), new _M0TPB5ArrayGiE([-1, -2, -1, 0, 0, 0, 1, 2, 1], 9));
}
function _M0MP270717lee10pixelforge5Image9threshold(self, level) {
  return _M0MP270717lee10pixelforge5Image8map__rgb(self, (r, g, b) => {
    const y = (((Math.imul(299, r) | 0) + (Math.imul(587, g) | 0) | 0) + (Math.imul(114, b) | 0) | 0) / 1000 | 0;
    const v = y >= level ? 255 : 0;
    return { _0: v, _1: v, _2: v };
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
          const _p = _M0MPC16double6Double7to__int(((base >>> 0 < _tmp$4.length ? _tmp$4[base] : $oob()) + 0) * factor + 0.5);
          if (base >>> 0 < _tmp$3.length) {
            _tmp$3[base] = _p < 0 ? 0 : _p > 255 ? 255 : _p & 255;
          } else {
            $oob();
          }
          const _tmp$5 = out.data;
          const _tmp$6 = base + 1 | 0;
          const _tmp$7 = out.data;
          const _tmp$8 = base + 1 | 0;
          const _p$2 = _M0MPC16double6Double7to__int(((_tmp$8 >>> 0 < _tmp$7.length ? _tmp$7[_tmp$8] : $oob()) + 0) * factor + 0.5);
          if (_tmp$6 >>> 0 < _tmp$5.length) {
            _tmp$5[_tmp$6] = _p$2 < 0 ? 0 : _p$2 > 255 ? 255 : _p$2 & 255;
          } else {
            $oob();
          }
          const _tmp$9 = out.data;
          const _tmp$10 = base + 2 | 0;
          const _tmp$11 = out.data;
          const _tmp$12 = base + 2 | 0;
          const _p$3 = _M0MPC16double6Double7to__int(((_tmp$12 >>> 0 < _tmp$11.length ? _tmp$11[_tmp$12] : $oob()) + 0) * factor + 0.5);
          if (_tmp$10 >>> 0 < _tmp$9.length) {
            _tmp$9[_tmp$10] = _p$3 < 0 ? 0 : _p$3 > 255 ? 255 : _p$3 & 255;
          } else {
            $oob();
          }
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
function _M0MP270717lee10pixelforge5Image11from__bytes(width, height, data) {
  const len = _M0FP270717lee10pixelforge20checked__buffer__len(width, height);
  if (data.length !== len) {
    $panic("Image::from_bytes: buffer length must equal width * height * 4");
  }
  return new _M0TP270717lee10pixelforge5Image(width, height, data);
}
function _M0MP270717lee10pixelforge5Image15histogram__luma(self) {
  return _M0MP270717lee10pixelforge5Image15luma__histogram(self);
}
function _M0FP370717lee10pixelforge3web13apply__filter(data, width, height, filter_id, amount) {
  return _M0MP270717lee10pixelforge5Image17apply__filter__id(_M0MP270717lee10pixelforge5Image11from__bytes(width, height, data), filter_id, amount).data;
}
function _M0FP370717lee10pixelforge3web11encode__png(data, width, height) {
  const bytes = _M0FP270717lee10pixelforge11png__encode(_M0MP270717lee10pixelforge5Image11from__bytes(width, height, data));
  const out = $makebytes(bytes.len, 0);
  const _bind = bytes.len;
  let _tmp = 0;
  while (true) {
    const i = _tmp;
    if (i < _bind) {
      if (i < 0 || i >= bytes.len) {
        $panic();
      }
      if (i >>> 0 < out.length) {
        out[i] = bytes.buf[i];
      } else {
        $oob();
      }
      _tmp = i + 1 | 0;
      continue;
    } else {
      break;
    }
  }
  return out;
}
function _M0FP370717lee10pixelforge3web15luma__histogram(data, width, height) {
  return _M0MP270717lee10pixelforge5Image15histogram__luma(_M0MP270717lee10pixelforge5Image11from__bytes(width, height, data));
}
export { _M0FP370717lee10pixelforge3web13apply__filter as apply_filter, _M0FP370717lee10pixelforge3web11encode__png as encode_png, _M0FP370717lee10pixelforge3web15luma__histogram as luma_histogram }
