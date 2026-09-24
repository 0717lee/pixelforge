// PixelForge compatibility facade for the independent 0717lee/moonav1 module.
// AV1/AVIF algorithms are maintained in MoonAV1; Image and avif_encode remain here.
// Pixel adapters preserve the existing RGBA buffer without copying it.

///|
pub using @moonav1 {
  type Av1CdefConfig,
  type Av1CdefParams,
  type Av1FilmGrainParams,
  type Av1FrameCdfs,
  type Av1FrameHeaderInfo,
  type Av1FrameInfo,
  type Av1FrameMap,
  type Av1InterBlock,
  type Av1InterFrame,
  type Av1LoopFilterBlockMap,
  type Av1LoopFilterConfig,
  type Av1MotionField,
  type Av1MotionFieldGrid,
  type Av1MotionRequest,
  type Av1MvBlock,
  type Av1MvFrame,
  type Av1MvStack,
  type Av1QuantDeltas,
  type Av1QuantMatrix,
  type Av1RefFrame,
  type Av1RestorationConfig,
  type Av1RestorationLayout,
  type Av1RestorationPlaneStripes,
  type Av1RestorationSourceView,
  type Av1RestorationStripeStore,
  type Av1RestorationTileState,
  type Av1RestorationType,
  type Av1RestorationUnit,
  type Av1RestorationUnitRecord,
  type Av1SbBlock,
  type Av1SbPartition,
  type Av1SbPartitionNode,
  type Av1SegmentationParams,
  type Av1SequenceInfo,
  type Av1ShowExistingFrameConfig,
  type Av1ShowExistingFrameEnvelope,
  type Av1Stage1Input,
  type Av1TilePayload,
  type Av1TxDepthState,
  type Av1TxLeaf,
  type Av1TxNode,
  type Av1TxPartition,
  type Av1TxTraversalState,
  type Av1TxType,
  type Av1VideoDecoder,
  type Av1WarpModel,
  type AvifAlphaExtent,
  type AvifAlphaItemDescriptor,
  type AvifAnimationDescriptor,
  type AvifAnimationFrame,
  type AvifContainer,
  type AvifGridDescriptor,
  type AvifGridExtent,
  type AvifGridTile,
  av1_apply_film_grain_planes,
  av1_cdef_filter_plane,
  av1_cdef_filter_yuv420,
  av1_coeff_base_default,
  av1_coeff_base_eob_default,
  av1_coeff_br_default,
  av1_coeff_dc_sign_default,
  av1_coeff_eob1024_default,
  av1_coeff_eob_extra_default,
  av1_coeff_eob_small_default,
  av1_decode_alpha,
  av1_decode_alpha_tile,
  av1_decode_partition_leaves,
  av1_decode_tx_partition_tree_payload,
  av1_extract_tile_payloads,
  av1_find_mv_stack,
  av1_frame_info,
  av1_frame_map,
  av1_frame_map_show,
  av1_frame_tile_payloads,
  av1_inter_frame_of,
  av1_inter_frame_supported,
  av1_intra_predict,
  av1_inverse_dct,
  av1_inverse_dct_2d,
  av1_inverse_dct_dc,
  av1_inverse_transform_2d,
  av1_motion_field,
  av1_motion_field_estimation,
  av1_motion_field_store,
  av1_msac_decode_first,
  av1_msac_read_first,
  av1_mv_block_position,
  av1_mv_div_mult_size,
  av1_mv_frame_of,
  av1_mv_invalid,
  av1_mv_max_frame_distance,
  av1_mv_max_offset_height,
  av1_mv_max_offset_width,
  av1_mv_projection,
  av1_mv_projection_component,
  av1_mv_refmvs_limit,
  av1_mv_stack_stamp,
  av1_parse_show_existing_frame,
  av1_parse_show_existing_frame_envelope,
  av1_parse_stage1_frame,
  av1_partition_children,
  av1_partition_context,
  av1_partition_leaves,
  av1_partition_node,
  av1_reconstruct_split_yuv420,
  av1_reconstruct_split_yuv420_with_types,
  av1_reconstruct_tx_chroma,
  av1_reconstruct_tx_luma,
  av1_relative_dist,
  av1_restoration_active,
  av1_seg_level_alt_q,
  av1_seg_level_ref_frame,
  av1_segment_levels,
  av1_segmentation_features_supported,
  av1_segmentation_supported,
  av1_segments,
  av1_sequence_info,
  av1_tx_children,
  av1_tx_depth_context_for_node,
  av1_tx_depth_context_from_neighbors,
  av1_tx_depth_context_from_sizes,
  av1_tx_leaves,
  av1_tx_rect_supported,
  av1_tx_traversal_record,
  av1_tx_traversal_state,
  av1_video_decoder,
  av1_warp_from_global_motion,
  av1_warp_samples_scan_limit,
  av1_wedge_mask,
  av1_wedge_shape_ok,
  avif_alpha_item_descriptor,
  avif_alpha_item_payload,
  avif_animation_descriptor,
  avif_animation_sample_payloads,
  avif_container_parse,
  avif_decode_alpha,
  avif_grid_descriptor,
  avif_stage1_input,
}

///|
pub const AV1_INTRA_DC : Int = 0

///|
pub const AV1_INTRA_H : Int = 2

///|
pub const AV1_INTRA_PAETH : Int = 12

///|
pub const AV1_INTRA_SMOOTH : Int = 9

///|
pub const AV1_INTRA_SMOOTH_H : Int = 11

///|
pub const AV1_INTRA_SMOOTH_V : Int = 10

///|
pub const AV1_INTRA_V : Int = 1

///|
pub(all) struct Av1ReferenceState {
  images : Array[Image?]
  frame_types : Array[Int]
}

///|
pub struct AvifAnimationPixelFrame {
  index : Int
  timestamp : Int
  duration : Int
  timescale : Int
  image : Image
}

///|
pub struct AvifAnimationPixels {
  timescale : Int
  frames : Array[AvifAnimationPixelFrame]
}

///|
fn moonav1_image_to_pixelforge(image : @moonav1.Image) -> Image {
  { width: image.width, height: image.height, data: image.data, }
}

///|
fn pixelforge_image_to_moonav1(image : Image) -> @moonav1.Image {
  { width: image.width, height: image.height, data: image.data, }
}

///|
fn moonav1_animation_frame_to_pixelforge(
  frame : @moonav1.AvifAnimationPixelFrame,
) -> AvifAnimationPixelFrame {
  {
    index: frame.index,
    timestamp: frame.timestamp,
    duration: frame.duration,
    timescale: frame.timescale,
    image: moonav1_image_to_pixelforge(frame.image),
  }
}

///|
fn moonav1_animation_to_pixelforge(
  animation : @moonav1.AvifAnimationPixels,
) -> AvifAnimationPixels {
  {
    timescale: animation.timescale,
    frames: animation.frames.map(moonav1_animation_frame_to_pixelforge),
  }
}

///|
// Source signature and defaults: av1_alpha_decode.mbt:301.
pub fn av1_apply_alpha(image : Image, alpha : Array[Byte]) -> Image? {
  @moonav1.av1_apply_alpha(pixelforge_image_to_moonav1(image), alpha).map(
    moonav1_image_to_pixelforge,
  )
}

///|
// Source signature and defaults: av1_tile_decode.mbt:467.
pub fn av1_decode(data : Array[Byte]) -> Image? {
  @moonav1.av1_decode(data).map(moonav1_image_to_pixelforge)
}

///|
// Source signature and defaults: av1_tile_decode.mbt:188.
pub fn av1_decode_dc_tile(
  width : Int,
  height : Int,
  tile_payload : Array[Byte],
  base_q_idx : Int,
  disable_cdf_update? : Bool = false,
  full_range? : Bool = false,
  matrix_coefficients? : Int = 6,
  use_128x128_superblock? : Bool = false,
  bit_depth? : Int = 8,
  allow_screen_content_tools? : Bool = false,
  tx_mode_select? : Bool = false,
  reduced_tx_set? : Bool = false,
  enable_filter_intra? : Bool = false,
  enable_intra_edge_filter? : Bool = false,
  cdef? : Av1CdefConfig? = None,
  loop_filter? : Av1LoopFilterConfig? = None,
  restoration? : Av1RestorationConfig? = None,
  upscaled_width? : Int = 0,
  superres_denom? : Int = 8,
) -> Image? {
  @moonav1.av1_decode_dc_tile(
    width,
    height,
    tile_payload,
    base_q_idx,
    disable_cdf_update~,
    full_range~,
    matrix_coefficients~,
    use_128x128_superblock~,
    bit_depth~,
    allow_screen_content_tools~,
    tx_mode_select~,
    reduced_tx_set~,
    enable_filter_intra~,
    enable_intra_edge_filter~,
    cdef~,
    loop_filter~,
    restoration~,
    upscaled_width~,
    superres_denom~,
  ).map(moonav1_image_to_pixelforge)
}

///|
// Preserves local pixel ownership; source: av1_reference_state.mbt:48.
pub fn av1_decode_show_existing_frame(
  frame_payload : Array[Byte],
  state : Av1ReferenceState,
  config : Av1ShowExistingFrameConfig,
) -> Image? {
  let envelope = match
    @moonav1.av1_parse_show_existing_frame(frame_payload, config) {
    Some(value) => value
    None => return None
  }
  av1_reference_show_existing(state, envelope)
}

///|
// Source signature and defaults: av1_split_tile_decode.mbt:64.
pub fn av1_decode_split_tile_64x64(
  tile_payload : Array[Byte],
  base_q_idx : Int,
  disable_cdf_update? : Bool = false,
  full_range? : Bool = false,
  matrix_coefficients? : Int = 6,
  use_128x128_superblock? : Bool = false,
  allow_screen_content_tools? : Bool = false,
) -> Image? {
  @moonav1.av1_decode_split_tile_64x64(
    tile_payload,
    base_q_idx,
    disable_cdf_update~,
    full_range~,
    matrix_coefficients~,
    use_128x128_superblock~,
    allow_screen_content_tools~,
  ).map(moonav1_image_to_pixelforge)
}

///|
// Source signature and defaults: av1_tile_decode.mbt:264.
pub fn av1_decode_tile_group(
  width : Int,
  height : Int,
  tile_cols : Int,
  tile_rows : Int,
  tile_payload : Array[Byte],
  tile_size_bytes : Int,
  base_q_idx : Int,
  disable_cdf_update? : Bool = false,
  full_range? : Bool = false,
  matrix_coefficients? : Int = 6,
  use_128x128_superblock? : Bool = false,
  bit_depth? : Int = 8,
  allow_screen_content_tools? : Bool = false,
  tx_mode_select? : Bool = false,
  reduced_tx_set? : Bool = false,
  enable_filter_intra? : Bool = false,
  enable_intra_edge_filter? : Bool = false,
  cdef? : Av1CdefConfig? = None,
  loop_filter? : Av1LoopFilterConfig? = None,
  restoration? : Av1RestorationConfig? = None,
  upscaled_width? : Int = 0,
  superres_denom? : Int = 8,
) -> Image? {
  @moonav1.av1_decode_tile_group(
    width,
    height,
    tile_cols,
    tile_rows,
    tile_payload,
    tile_size_bytes,
    base_q_idx,
    disable_cdf_update~,
    full_range~,
    matrix_coefficients~,
    use_128x128_superblock~,
    bit_depth~,
    allow_screen_content_tools~,
    tx_mode_select~,
    reduced_tx_set~,
    enable_filter_intra~,
    enable_intra_edge_filter~,
    cdef~,
    loop_filter~,
    restoration~,
    upscaled_width~,
    superres_denom~,
  ).map(moonav1_image_to_pixelforge)
}

///|
// Source signature and defaults: av1_tile_decode.mbt:393.
pub fn av1_decode_tile_group_with_boundaries(
  width : Int,
  height : Int,
  tile_col_starts_sb : Array[Int],
  tile_row_starts_sb : Array[Int],
  superblock_pixels : Int,
  tile_payload : Array[Byte],
  tile_size_bytes : Int,
  base_q_idx : Int,
  disable_cdf_update? : Bool = false,
  full_range? : Bool = false,
  matrix_coefficients? : Int = 6,
  use_128x128_superblock? : Bool = false,
  bit_depth? : Int = 8,
  allow_screen_content_tools? : Bool = false,
  tx_mode_select? : Bool = false,
  reduced_tx_set? : Bool = false,
  enable_filter_intra? : Bool = false,
  enable_intra_edge_filter? : Bool = false,
  cdef? : Av1CdefConfig? = None,
  loop_filter? : Av1LoopFilterConfig? = None,
  restoration? : Av1RestorationConfig? = None,
  upscaled_width? : Int = 0,
  monochrome? : Bool = false,
  superres_denom? : Int = 8,
) -> Image? {
  @moonav1.av1_decode_tile_group_with_boundaries(
    width,
    height,
    tile_col_starts_sb,
    tile_row_starts_sb,
    superblock_pixels,
    tile_payload,
    tile_size_bytes,
    base_q_idx,
    disable_cdf_update~,
    full_range~,
    matrix_coefficients~,
    use_128x128_superblock~,
    bit_depth~,
    allow_screen_content_tools~,
    tx_mode_select~,
    reduced_tx_set~,
    enable_filter_intra~,
    enable_intra_edge_filter~,
    cdef~,
    loop_filter~,
    restoration~,
    upscaled_width~,
    monochrome~,
    superres_denom~,
  ).map(moonav1_image_to_pixelforge)
}

///|
// Source signature and defaults: av1_block_reconstruct.mbt:318.
pub fn av1_reconstruct_split_64x64(
  y_coeffs : Array[Array[Int]],
  u_coeffs : Array[Array[Int]],
  v_coeffs : Array[Array[Int]],
  y_modes : Array[Int],
  u_modes : Array[Int],
  v_modes : Array[Int],
  full_range? : Bool = false,
  matrix_coefficients? : Int = 6,
) -> Image? {
  @moonav1.av1_reconstruct_split_64x64(
    y_coeffs,
    u_coeffs,
    v_coeffs,
    y_modes,
    u_modes,
    v_modes,
    full_range~,
    matrix_coefficients~,
  ).map(moonav1_image_to_pixelforge)
}

///|
// Source signature and defaults: av1_block_reconstruct.mbt:209.
pub fn av1_reconstruct_tx_rgba(
  width : Int,
  height : Int,
  y_leaves : Array[Av1TxLeaf],
  y_coefficients : Array[Array[Int]],
  u_leaves : Array[Av1TxLeaf],
  u_coefficients : Array[Array[Int]],
  v_leaves : Array[Av1TxLeaf],
  v_coefficients : Array[Array[Int]],
  y_mode : Int,
  uv_mode : Int,
  y_types : Array[Av1TxType],
  u_types : Array[Av1TxType],
  v_types : Array[Av1TxType],
  bit_depth : Int,
  full_range? : Bool = false,
  matrix_coefficients? : Int = 6,
) -> Image? {
  @moonav1.av1_reconstruct_tx_rgba(
    width,
    height,
    y_leaves,
    y_coefficients,
    u_leaves,
    u_coefficients,
    v_leaves,
    v_coefficients,
    y_mode,
    uv_mode,
    y_types,
    u_types,
    v_types,
    bit_depth,
    full_range~,
    matrix_coefficients~,
  ).map(moonav1_image_to_pixelforge)
}

///|
// Preserves local pixel ownership; source: av1_reference_state.mbt:35.
pub fn av1_reference_show_existing(
  state : Av1ReferenceState,
  envelope : Av1ShowExistingFrameEnvelope,
) -> Image? {
  if envelope.frame_to_show_map_idx < 0 || envelope.frame_to_show_map_idx >= 8 {
    return None
  }
  state.images[envelope.frame_to_show_map_idx].map(fn(image) { image.copy() })
}

///|
// Preserves local pixel ownership; source: av1_reference_state.mbt:12.
pub fn av1_reference_state() -> Av1ReferenceState {
  { images: Array::make(8, None), frame_types: Array::make(8, -1), }
}

///|
// Preserves local pixel ownership; source: av1_reference_state.mbt:20.
pub fn av1_reference_store(
  state : Av1ReferenceState,
  slot : Int,
  image : Image,
  frame_type : Int,
) -> Bool {
  if slot < 0 || slot >= 8 || frame_type < 0 || frame_type > 3 {
    return false
  }
  state.images[slot] = Some(image.copy())
  state.frame_types[slot] = frame_type
  true
}

///|
// Source signature and defaults: av1_video_decode.mbt:27.
pub fn av1_video_decode_frame(
  decoder : Av1VideoDecoder,
  data : Array[Byte],
  allow_monochrome? : Bool = false,
) -> Image? {
  @moonav1.av1_video_decode_frame(decoder, data, allow_monochrome~).map(
    moonav1_image_to_pixelforge,
  )
}

///|
// Source signature and defaults: av1_video_decode.mbt:50.
pub fn av1_video_decode_temporal_unit(
  decoder : Av1VideoDecoder,
  data : Array[Byte],
  allow_monochrome? : Bool = false,
) -> Array[Image]? {
  @moonav1.av1_video_decode_temporal_unit(decoder, data, allow_monochrome~).map(fn(
      images,
    ) {
      images.map(moonav1_image_to_pixelforge)
    },
  )
}

///|
// Source signature and defaults: av1_predict_highbd.mbt:232.
pub fn av1_yuv420_highbd_to_rgba(
  width : Int,
  height : Int,
  y : Array[Int],
  u : Array[Int],
  v : Array[Int],
  bit_depth : Int,
  full_range? : Bool = false,
  matrix_coefficients? : Int = 6,
  color_primaries? : Int = 2,
  transfer_characteristics? : Int = 2,
) -> Image? {
  @moonav1.av1_yuv420_highbd_to_rgba(
    width,
    height,
    y,
    u,
    v,
    bit_depth,
    full_range~,
    matrix_coefficients~,
    color_primaries~,
    transfer_characteristics~,
  ).map(moonav1_image_to_pixelforge)
}

///|
// Source signature and defaults: av1_predict.mbt:7.
pub fn av1_yuv420_to_rgba(
  width : Int,
  height : Int,
  y : Array[Byte],
  u : Array[Byte],
  v : Array[Byte],
) -> Image? {
  @moonav1.av1_yuv420_to_rgba(width, height, y, u, v).map(
    moonav1_image_to_pixelforge,
  )
}

///|
// Source signature and defaults: av1_predict.mbt:50.
pub fn av1_yuv420_to_rgba_color(
  width : Int,
  height : Int,
  y : Array[Byte],
  u : Array[Byte],
  v : Array[Byte],
  full_range? : Bool = false,
  matrix_coefficients? : Int = 6,
  color_primaries? : Int = 2,
  transfer_characteristics? : Int = 2,
) -> Image? {
  @moonav1.av1_yuv420_to_rgba_color(
    width,
    height,
    y,
    u,
    v,
    full_range~,
    matrix_coefficients~,
    color_primaries~,
    transfer_characteristics~,
  ).map(moonav1_image_to_pixelforge)
}

///|
// Source signature and defaults: av1_predict.mbt:27.
pub fn av1_yuv420_to_rgba_range(
  width : Int,
  height : Int,
  y : Array[Byte],
  u : Array[Byte],
  v : Array[Byte],
  full_range? : Bool = false,
) -> Image? {
  @moonav1.av1_yuv420_to_rgba_range(width, height, y, u, v, full_range~).map(
    moonav1_image_to_pixelforge,
  )
}

///|
// Source signature and defaults: av1_predict_highbd.mbt:17.
pub fn av1_yuv_highbd_to_rgba(
  width : Int,
  height : Int,
  y : Array[Int],
  u : Array[Int],
  v : Array[Int],
  bit_depth : Int,
  subsampling_x? : Bool = true,
  subsampling_y? : Bool = true,
  full_range? : Bool = false,
  matrix_coefficients? : Int = 6,
  color_primaries? : Int = 2,
  transfer_characteristics? : Int = 2,
) -> Image? {
  @moonav1.av1_yuv_highbd_to_rgba(
    width,
    height,
    y,
    u,
    v,
    bit_depth,
    subsampling_x~,
    subsampling_y~,
    full_range~,
    matrix_coefficients~,
    color_primaries~,
    transfer_characteristics~,
  ).map(moonav1_image_to_pixelforge)
}

///|
// Preserves local pixel ownership; source: avif_grid_animation.mbt:262.
pub fn avif_animation_frame_at(
  animation : AvifAnimationPixels,
  timestamp : Int,
) -> Image? {
  if timestamp < 0 || animation.timescale <= 0 || animation.frames.length() == 0 {
    return None
  }
  let mut total = 0
  for frame in animation.frames {
    if frame.duration <= 0 {
      return None
    }
    let next_total = total + frame.duration
    if next_total < total {
      return None
    }
    total = next_total
  }
  if total <= 0 {
    return None
  }
  let t = timestamp % total
  for frame in animation.frames {
    if t < frame.timestamp + frame.duration {
      return Some(frame.image)
    }
  }
  Some(animation.frames[animation.frames.length() - 1].image)
}

///|
// Source signature and defaults: av1_tile_decode.mbt:477.
pub fn avif_decode(data : Array[Byte]) -> Image? {
  @moonav1.avif_decode(data).map(moonav1_image_to_pixelforge)
}

///|
// Source signature and defaults: avif_grid_animation.mbt:177.
pub fn avif_decode_animation(data : Array[Byte]) -> AvifAnimationPixels? {
  @moonav1.avif_decode_animation(data).map(moonav1_animation_to_pixelforge)
}

///|
// Source signature and defaults: avif_grid_animation.mbt:248.
pub fn avif_decode_animation_frame(
  data : Array[Byte],
  timestamp : Int,
) -> Image? {
  @moonav1.avif_decode_animation_frame(data, timestamp).map(
    moonav1_image_to_pixelforge,
  )
}

///|
// Source signature and defaults: avif_grid_animation.mbt:67.
pub fn avif_decode_animation_frames(
  descriptor : AvifAnimationDescriptor,
  samples : Array[Array[Byte]],
) -> AvifAnimationPixels? {
  @moonav1.avif_decode_animation_frames(descriptor, samples).map(
    moonav1_animation_to_pixelforge,
  )
}

///|
// Source signature and defaults: avif_grid_animation.mbt:124.
pub fn avif_decode_animation_samples(
  timescale : Int,
  timestamps : Array[Int],
  durations : Array[Int],
  samples : Array[Array[Byte]],
) -> AvifAnimationPixels? {
  @moonav1.avif_decode_animation_samples(
    timescale, timestamps, durations, samples,
  ).map(moonav1_animation_to_pixelforge)
}

///|
// Source signature and defaults: avif_grid_reconstruct.mbt:106.
pub fn avif_decode_grid(
  data : Array[Byte],
  descriptor : AvifGridDescriptor,
) -> Image? {
  @moonav1.avif_decode_grid(data, descriptor).map(moonav1_image_to_pixelforge)
}

///|
// Source signature and defaults: avif_grid_reconstruct.mbt:133.
pub fn avif_decode_grid_auto(data : Array[Byte]) -> Image? {
  @moonav1.avif_decode_grid_auto(data).map(moonav1_image_to_pixelforge)
}

///|
// Source signature and defaults: avif_grid_reconstruct.mbt:77.
pub fn avif_decode_grid_tiles(
  rows : Int,
  columns : Int,
  output_width : Int,
  output_height : Int,
  samples : Array[Array[Byte]],
) -> Image? {
  @moonav1.avif_decode_grid_tiles(
    rows, columns, output_width, output_height, samples,
  ).map(moonav1_image_to_pixelforge)
}

///|
// Source signature and defaults: av1_alpha_decode.mbt:195.
pub fn avif_decode_rgba(data : Array[Byte]) -> Image? {
  @moonav1.avif_decode_rgba(data).map(moonav1_image_to_pixelforge)
}

///|
// Source signature and defaults: avif_grid_reconstruct.mbt:6.
pub fn avif_reconstruct_grid(
  rows : Int,
  columns : Int,
  output_width : Int,
  output_height : Int,
  tiles : Array[Image],
) -> Image? {
  @moonav1.avif_reconstruct_grid(
    rows,
    columns,
    output_width,
    output_height,
    tiles.map(pixelforge_image_to_moonav1),
  ).map(moonav1_image_to_pixelforge)
}
