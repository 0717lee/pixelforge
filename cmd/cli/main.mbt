///|
/// PixelForge's small, cross-backend CLI.
///
/// The command deliberately accepts bytes as hex instead of opening files. MoonBit's
/// portable core has no common filesystem API across native, JS and wasm-gc. A shell
/// can feed a file as hex (`xxd -p`) and the same command then works on every backend.
///
///   moon run cmd/cli -- info --input-hex <png-hex>
///   moon run cmd/cli -- convert --from png --to qoi --input-hex <png-hex>
fn main {
  let args = @env.args()
  if args.length() < 2 {
    print_help()
    return
  }
  let command = args[1]
  if command == "help" || command == "--help" || command == "-h" {
    print_help()
    return
  }
  if command == "info" {
    info(args, 2)
  } else if command == "convert" {
    convert(args, 2)
  } else {
    abort("pixelforge: unknown command '\{command}'. Use --help for usage.")
  }
}

///|
fn print_help() -> Unit {
  println("PixelForge CLI 0.15")
  println("Portable codec utility (input is hexadecimal bytes)")
  println("")
  println("Usage:")
  println("  pixelforge info --input-hex HEX")
  println("  pixelforge convert --from FORMAT --to FORMAT --input-hex HEX")
  println("")
  println("Formats: png, qoi, bmp, gif (GIF output is not supported yet)")
  println("The command prints metadata and converted bytes as hexadecimal.")
}

///|
fn info(args : Array[String], start : Int) -> Unit {
  let hex = option(args, start, "--input-hex")
  let bytes = decode_hex(hex)
  let format = detect_format(bytes)
  let image = decode_image(format, bytes)
  println("format=\{format}")
  println("width=\{image.width}")
  println("height=\{image.height}")
  println("channels=4")
  println("bytes=\{bytes.length()}")
}

///|
fn convert(args : Array[String], start : Int) -> Unit {
  let from = option(args, start, "--from")
  let to = option(args, start, "--to")
  let bytes = decode_hex(option(args, start, "--input-hex"))
  let actual = detect_format(bytes)
  if actual != from {
    abort("pixelforge: input format is \{actual}, but --from=\{from}")
  }
  let image = decode_image(from, bytes)
  let output = encode_image(to, image)
  println("format=\{to}")
  println("width=\{image.width}")
  println("height=\{image.height}")
  println("bytes=\{output.length()}")
  println("hex=\{encode_hex(output)}")
}

///|
fn option(args : Array[String], start : Int, name : String) -> String {
  let mut i = start
  while i < args.length() {
    if args[i] == name {
      if i + 1 >= args.length() {
        abort("pixelforge: missing value for \{name}")
      }
      return args[i + 1]
    }
    i += 1
  }
  abort("pixelforge: missing required option \{name}. Use --help for usage.")
}

///|
fn hex_digit(ch : Char) -> Int {
  match ch {
    '0'..='9' => ch.to_int() - '0'.to_int()
    'a'..='f' => ch.to_int() - 'a'.to_int() + 10
    'A'..='F' => ch.to_int() - 'A'.to_int() + 10
    _ => abort("pixelforge: invalid hexadecimal digit '\{ch}'")
  }
}

///|
fn decode_hex(text : String) -> Array[Byte] {
  let chars = []
  for ch in text {
    if ch != ' ' && ch != '\n' && ch != '\r' && ch != '\t' {
      chars.push(ch)
    }
  }
  if chars.length() == 0 || chars.length() % 2 != 0 {
    abort(
      "pixelforge: --input-hex must contain a non-empty even number of hexadecimal digits",
    )
  }
  let out = []
  let mut i = 0
  while i < chars.length() {
    out.push((hex_digit(chars[i]) * 16 + hex_digit(chars[i + 1])).to_byte())
    i = i + 2
  }
  out
}

///|
fn encode_hex(bytes : Array[Byte]) -> String {
  let digits : Array[Char] = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  let out = []
  for b in bytes {
    let n = b.to_int()
    out.push(digits[n >> 4])
    out.push(digits[n & 15])
  }
  String::from_array(out)
}

///|
fn detect_format(bytes : Array[Byte]) -> String {
  if bytes.length() >= 8 &&
    bytes[0] == b'\x89' &&
    bytes[1] == b'P' &&
    bytes[2] == b'N' &&
    bytes[3] == b'G' {
    "png"
  } else if bytes.length() >= 4 &&
    bytes[0] == b'q' &&
    bytes[1] == b'o' &&
    bytes[2] == b'i' &&
    bytes[3] == b'f' {
    "qoi"
  } else if bytes.length() >= 2 && bytes[0] == b'B' && bytes[1] == b'M' {
    "bmp"
  } else if bytes.length() >= 6 &&
    bytes[0] == b'G' &&
    bytes[1] == b'I' &&
    bytes[2] == b'F' {
    "gif"
  } else {
    abort("pixelforge: unknown image signature")
  }
}

///|
fn decode_image(format : String, bytes : Array[Byte]) -> @pixelforge.Image {
  match format {
    "png" =>
      @pixelforge.png_decode(bytes).unwrap_or_else(() => {
        abort("pixelforge: PNG decode failed")
      })
    "qoi" =>
      @pixelforge.qoi_decode(bytes).unwrap_or_else(() => {
        abort("pixelforge: QOI decode failed")
      })
    "bmp" =>
      @pixelforge.bmp_decode(bytes).unwrap_or_else(() => {
        abort("pixelforge: BMP decode failed")
      })
    "gif" =>
      @pixelforge.gif_decode(bytes).unwrap_or_else(() => {
        abort("pixelforge: GIF decode failed")
      })
    _ => abort("pixelforge: unsupported input format \{format}")
  }
}

///|
fn encode_image(format : String, image : @pixelforge.Image) -> Array[Byte] {
  match format {
    "png" => @pixelforge.png_encode(image)
    "qoi" => @pixelforge.qoi_encode(image)
    "bmp" => @pixelforge.bmp_encode(image, true)
    "gif" => abort("pixelforge: GIF encoding is not supported yet")
    _ => abort("pixelforge: unsupported output format {format}")
  }
}
