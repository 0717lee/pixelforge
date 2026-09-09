///|
/// PixelForge's small native CLI (with a portable hexadecimal mode).
///
/// Native builds accept file paths. `--input-hex` remains available for
/// deterministic host-independent invocations.
///
///   moon run --target native cmd/cli -- info --input image.png
///   moon run --target native cmd/cli -- convert --from png --to qoi --input image.png --output image.qoi
///   moon run --target native cmd/cli -- convert --from png --to png --pipeline grayscale,invert --input image.png --output filtered.png
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
  println("Native codec utility (file paths or hexadecimal bytes)")
  println("")
  println("Usage:")
  println("  pixelforge info --input PATH")
  println("  pixelforge convert --from FORMAT --to FORMAT [--pipeline OPS] --input PATH --output PATH")
  println("  pixelforge info --input-hex HEX")
  println("  pixelforge convert --from FORMAT --to FORMAT --input-hex HEX")
  println("")
  println("Formats: png, qoi, bmp, gif, jpeg, webp, avif, tiff")
  println("Pipeline ops: grayscale,invert,brightness:N,contrast:N,blur,sharpen,emboss,edges,sobel,sepia,threshold:N,pixelate:N,median,histogram-equalize,flip-horizontal,flip-vertical,posterize:N,gamma:N,vignette:N,scharr,canny:N,otsu,dither-mono")
  println("File mode writes converted bytes to --output; hex mode prints bytes as hexadecimal.")
}

///|
fn info(args : Array[String], start : Int) -> Unit {
  let bytes = input_bytes(args, start)
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
  let file_mode = has_option(args, start, "--input")
  let bytes = input_bytes(args, start)
  let actual = detect_format(bytes)
  if actual != from {
    abort("pixelforge: input format is \{actual}, but --from=\{from}")
  }
  let image = decode_image(from, bytes)
  let filtered = apply_pipeline_option(args, start, image)
  let output = encode_image(to, filtered)
  if file_mode {
    let output_path = option(args, start, "--output")
    write_file(output_path, output)
    println("format=\{to}")
    println("width=\{image.width}")
    println("height=\{image.height}")
    println("bytes=\{output.length()}")
    println("output=\{output_path}")
  } else {
    println("format=\{to}")
    println("width=\{image.width}")
    println("height=\{image.height}")
    println("bytes=\{output.length()}")
    println("hex=\{encode_hex(output)}")
  }
}

/// Apply the optional comma-separated pipeline. Each operation may include a
/// numeric argument after `:` (for example `brightness:20,gamma:1.2`).
fn apply_pipeline_option(
  args : Array[String],
  start : Int,
  image : @pixelforge.Image,
) -> @pixelforge.Image {
  if !has_option(args, start, "--pipeline") {
    return image
  }
  let spec = option(args, start, "--pipeline")
  if spec.trim() == "" {
    abort("pixelforge: --pipeline must contain at least one operation")
  }
  let mut pipeline = @pixelforge.Pipeline::new()
  for raw in spec.split(",") {
    let token = raw.to_owned().trim().to_owned()
    if token == "" {
      abort("pixelforge: --pipeline contains an empty operation")
    }
    let parts = token.split(":").collect()
    if parts.length() > 2 {
      abort("pixelforge: invalid pipeline operation '\{token}'")
    }
    let name = parts[0].to_owned().trim().to_owned()
    let value = if parts.length() == 2 {
      Some(parts[1].to_owned().trim().to_owned())
    } else {
      None
    }
    let filter = pipeline_filter(name, value, token)
    pipeline = pipeline.append(filter)
  }
  image.apply_pipeline(pipeline)
}

fn pipeline_filter(
  name : String,
  value : Option[String],
  token : String,
) -> @pixelforge.Filter {
  match name {
    "grayscale" => no_pipeline_value(name, value, token, @pixelforge.Filter::Grayscale)
    "invert" => no_pipeline_value(name, value, token, @pixelforge.Filter::Invert)
    "brightness" => @pixelforge.Filter::Brightness(parse_pipeline_int(value, name, token))
    "contrast" => @pixelforge.Filter::Contrast(parse_pipeline_double(value, name, token))
    "blur" => no_pipeline_value(name, value, token, @pixelforge.Filter::Blur)
    "sharpen" => no_pipeline_value(name, value, token, @pixelforge.Filter::Sharpen)
    "emboss" => no_pipeline_value(name, value, token, @pixelforge.Filter::Emboss)
    "edges" => no_pipeline_value(name, value, token, @pixelforge.Filter::Edges)
    "sobel" => no_pipeline_value(name, value, token, @pixelforge.Filter::Sobel)
    "sepia" => no_pipeline_value(name, value, token, @pixelforge.Filter::Sepia)
    "threshold" => @pixelforge.Filter::Threshold(parse_pipeline_int(value, name, token))
    "pixelate" => @pixelforge.Filter::Pixelate(parse_pipeline_int(value, name, token))
    "median" => no_pipeline_value(name, value, token, @pixelforge.Filter::Median)
    "histogram-equalize" => no_pipeline_value(name, value, token, @pixelforge.Filter::HistogramEqualize)
    "flip-horizontal" => no_pipeline_value(name, value, token, @pixelforge.Filter::FlipHorizontal)
    "flip-vertical" => no_pipeline_value(name, value, token, @pixelforge.Filter::FlipVertical)
    "posterize" => @pixelforge.Filter::Posterize(parse_pipeline_int(value, name, token))
    "gamma" => @pixelforge.Filter::Gamma(parse_pipeline_double(value, name, token))
    "vignette" => @pixelforge.Filter::Vignette(parse_pipeline_double(value, name, token))
    "scharr" => no_pipeline_value(name, value, token, @pixelforge.Filter::Scharr)
    "canny" => @pixelforge.Filter::Canny(parse_pipeline_int(value, name, token))
    "otsu" => no_pipeline_value(name, value, token, @pixelforge.Filter::Otsu)
    "dither-mono" => no_pipeline_value(name, value, token, @pixelforge.Filter::DitherMono)
    _ => abort("pixelforge: unknown pipeline operation '\{name}' in '\{token}'")
  }
}

fn no_pipeline_value(
  name : String,
  value : Option[String],
  token : String,
  filter : @pixelforge.Filter,
) -> @pixelforge.Filter {
  match value {
    Some(_) => abort("pixelforge: operation '\{name}' does not accept a value in '\{token}'")
    None => filter
  }
}

fn parse_pipeline_int(value : Option[String], _name : String, _token : String) -> Int {
  let text = match value {
    Some(v) if v != "" => v
    _ => abort("pixelforge: operation '\{_name}' requires an integer value in '\{_token}'")
  }
  try @string.parse_int(text) catch {
    _ => abort("pixelforge: invalid integer in pipeline operation '\{_token}'")
  }
}

fn parse_pipeline_double(value : Option[String], _name : String, _token : String) -> Double {
  let text = match value {
    Some(v) if v != "" => v
    _ => abort("pixelforge: operation '\{_name}' requires a number in '\{_token}'")
  }
  try @string.parse_double(text) catch {
    _ => abort("pixelforge: invalid number in pipeline operation '\{_token}'")
  }
}

/// Read either a native file path or portable hexadecimal bytes.
fn input_bytes(args : Array[String], start : Int) -> Array[Byte] {
  if has_option(args, start, "--input") {
    if has_option(args, start, "--input-hex") {
      abort("pixelforge: use only one of --input and --input-hex")
    }
    read_file(option(args, start, "--input"))
  } else {
    decode_hex(option(args, start, "--input-hex"))
  }
}

fn has_option(args : Array[String], start : Int, name : String) -> Bool {
  let mut i = start
  while i < args.length() {
    if args[i] == name {
      return true
    }
    i += 1
  }
  false
}

fn read_file(path : String) -> Array[Byte] {
  Bytes::to_array(@fs.read_file_to_bytes(path) catch {
    @fs.IOError(message) => abort("pixelforge: cannot read '\{path}': \{message}")
  })
}

fn write_file(path : String, bytes : Array[Byte]) -> Unit {
  @fs.write_bytes_to_file(path, Bytes::from_array(bytes)) catch {
    @fs.IOError(message) => abort("pixelforge: cannot write '\{path}': \{message}")
  }
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
  } else if bytes.length() >= 2 && bytes[0] == b'\xFF' && bytes[1] == b'\xD8' {
    "jpeg"
  } else if bytes.length() >= 12 && bytes[0] == b'R' && bytes[1] == b'I' && bytes[2] == b'F' && bytes[3] == b'F' &&
    bytes[8] == b'W' && bytes[9] == b'E' && bytes[10] == b'B' && bytes[11] == b'P' {
    "webp"
  } else if bytes.length() >= 8 && bytes[4] == b'f' && bytes[5] == b't' && bytes[6] == b'y' && bytes[7] == b'p' {
    "avif"
  } else if bytes.length() >= 4 &&
    ((bytes[0] == b'I' && bytes[1] == b'I' && bytes[2] == b'*' && bytes[3] == b'\x00') ||
      (bytes[0] == b'M' && bytes[1] == b'M' && bytes[2] == b'\x00' && bytes[3] == b'*')) {
    "tiff"
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
    "jpeg" =>
      @pixelforge.jpeg_decode(bytes).unwrap_or_else(() => {
        abort("pixelforge: JPEG decode failed")
      })
    "tiff" =>
      @pixelforge.tiff_decode(bytes).unwrap_or_else(() => {
        abort("pixelforge: TIFF decode failed or uses unsupported features")
      })
    "webp" => abort("pixelforge: WebP decode is not available on the native CLI")
    "avif" => abort("pixelforge: AVIF decode is not available on the native CLI")
    _ => abort("pixelforge: unsupported input format \{format}")
  }
}

///|
fn encode_image(format : String, image : @pixelforge.Image) -> Array[Byte] {
  match format {
    "png" => @pixelforge.png_encode(image)
    "qoi" => @pixelforge.qoi_encode(image)
    "bmp" => @pixelforge.bmp_encode(image, true)
    "gif" => @pixelforge.gif_encode(image)
    "jpeg" => @pixelforge.jpeg_encode(image, 90)
    "webp" => @pixelforge.webp_encode(image)
    "avif" => @pixelforge.avif_encode(image)
    "tiff" => abort("pixelforge: TIFF encoding is not supported")
    _ => abort("pixelforge: unsupported output format {format}")
  }
}
