/// Bounded AV1 partition-tree geometry helpers.
///
/// Coordinates and dimensions are expressed in pixels.  The AV1 reference
/// decoder stores the same values in 4x4 (MI) units; using pixels here keeps
/// this standalone model useful to the image reconstruction path while the
/// `partition_context` calculation converts sizes to the corresponding MI
/// logarithm.

/// AV1 partition symbols.  The first four are the symbols used by the staged
/// decoder; the extended forms are represented so a later walker can add them
/// without changing the public data model.
pub(all) enum Av1SbPartition {
  Av1SbPartitionNone
  Av1SbPartitionHorz
  Av1SbPartitionVert
  Av1SbPartitionSplit
  Av1SbPartitionHorzA
  Av1SbPartitionHorzB
  Av1SbPartitionVertA
  Av1SbPartitionVertB
  Av1SbPartitionHorz4
  Av1SbPartitionVert4
}

/// A rectangular node in a superblock partition tree.
pub(all) struct Av1SbPartitionNode {
  row : Int
  col : Int
  size : Int
  frame_width : Int
  frame_height : Int
}

/// Creates a square partition node.  Invalid geometry is rejected by the
/// child and edge predicates rather than clamped silently.
pub fn av1_partition_node(
  row : Int,
  col : Int,
  size : Int,
  frame_width : Int,
  frame_height : Int,
) -> Av1SbPartitionNode {
  { row, col, size, frame_width, frame_height }
}

/// Whether the lower half of this block lies inside the frame (AV1 `hasRows`).
pub fn Av1SbPartitionNode::has_rows(self : Av1SbPartitionNode) -> Bool {
  self.size > 0 && self.row >= 0 && self.row + self.size / 2 < self.frame_height
}

/// Whether the right half of this block lies inside the frame (AV1 `hasCols`).
pub fn Av1SbPartitionNode::has_cols(self : Av1SbPartitionNode) -> Bool {
  self.size > 0 && self.col >= 0 && self.col + self.size / 2 < self.frame_width
}

/// True when the node has no complete lower or right half.  AV1 forces a
/// split in this case, avoiding a partition symbol that would address pixels
/// outside the frame.
pub fn Av1SbPartitionNode::edge_forces_split(self : Av1SbPartitionNode) -> Bool {
  !self.has_rows() && !self.has_cols()
}

/// Convert a pixel block size to AV1's `MiWidthLog2` value.
fn av1_partition_size_log2(size : Int) -> Int {
  let mut mi = size / 4
  if mi < 1 {
    return 0
  }
  let mut out = 0
  while mi > 1 {
    mi = mi >> 1
    out = out + 1
  }
  out
}

/// AV1 `partitionCtx`: above contributes one and left contributes two when
/// the neighbouring block is smaller than the current block.
pub fn av1_partition_context(
  current_size : Int,
  above_size : Int?,
  left_size : Int?,
) -> Int {
  let current_log2 = av1_partition_size_log2(current_size)
  let above = match above_size {
    Some(size) => if av1_partition_size_log2(size) < current_log2 { 1 } else { 0 }
    None => 0
  }
  let left = match left_size {
    Some(size) => if av1_partition_size_log2(size) < current_log2 { 1 } else { 0 }
    None => 0
  }
  left * 2 + above
}

fn av1_partition_child(
  node : Av1SbPartitionNode,
  row : Int,
  col : Int,
  size : Int,
) -> Av1SbPartitionNode? {
  if row < 0 || col < 0 || row >= node.frame_height || col >= node.frame_width || size <= 0 {
    None
  } else {
    Some({
      row,
      col,
      size,
      frame_width: node.frame_width,
      frame_height: node.frame_height,
    })
  }
}

fn av1_partition_push_child(
  out : Array[Av1SbPartitionNode],
  child : Av1SbPartitionNode?,
) -> Unit {
  match child {
    Some(value) => out.push(value)
    None => ()
  }
}

/// Return in-frame child coordinates for a partition symbol.  `None` returns
/// the node itself as a leaf.  Split children are filtered at the frame edge,
/// matching the reference decoder's early out for rows/columns outside the
/// image.
pub fn av1_partition_children(
  node : Av1SbPartitionNode,
  partition : Av1SbPartition,
) -> Array[Av1SbPartitionNode] {
  let half = node.size / 2
  let out : Array[Av1SbPartitionNode] = []
  match partition {
    Av1SbPartitionNone => out.push(node)
    Av1SbPartitionHorz => {
      av1_partition_push_child(out, av1_partition_child(node, node.row, node.col, half))
      if node.has_rows() {
        av1_partition_push_child(
          out,
          av1_partition_child(node, node.row + half, node.col, half),
        )
      }
    }
    Av1SbPartitionVert => {
      av1_partition_push_child(out, av1_partition_child(node, node.row, node.col, half))
      if node.has_cols() {
        av1_partition_push_child(
          out,
          av1_partition_child(node, node.row, node.col + half, half),
        )
      }
    }
    Av1SbPartitionSplit => {
      av1_partition_push_child(out, av1_partition_child(node, node.row, node.col, half))
      av1_partition_push_child(
        out,
        av1_partition_child(node, node.row, node.col + half, half),
      )
      av1_partition_push_child(
        out,
        av1_partition_child(node, node.row + half, node.col, half),
      )
      av1_partition_push_child(
        out,
        av1_partition_child(node, node.row + half, node.col + half, half),
      )
    }
    // A/B partitions combine one full half with two quarter blocks.  The
    // children stay square in this geometry model; rectangular transform
    // leaves are handled by the separate tx tree.
    Av1SbPartitionHorzA => {
      av1_partition_push_child(out, av1_partition_child(node, node.row, node.col, half))
      av1_partition_push_child(out, av1_partition_child(node, node.row + half, node.col, half))
      av1_partition_push_child(out, av1_partition_child(node, node.row + half, node.col + half, half))
    }
    Av1SbPartitionHorzB => {
      av1_partition_push_child(out, av1_partition_child(node, node.row, node.col, half))
      av1_partition_push_child(out, av1_partition_child(node, node.row, node.col + half, half))
      av1_partition_push_child(out, av1_partition_child(node, node.row + half, node.col, half))
    }
    Av1SbPartitionVertA => {
      av1_partition_push_child(out, av1_partition_child(node, node.row, node.col, half))
      av1_partition_push_child(out, av1_partition_child(node, node.row + half, node.col, half))
      av1_partition_push_child(out, av1_partition_child(node, node.row, node.col + half, half))
    }
    Av1SbPartitionVertB => {
      av1_partition_push_child(out, av1_partition_child(node, node.row, node.col, half))
      av1_partition_push_child(out, av1_partition_child(node, node.row + half, node.col, half))
      av1_partition_push_child(out, av1_partition_child(node, node.row + half, node.col + half, half))
    }
    Av1SbPartitionHorz4 => {
      let quarter = node.size / 4
      if quarter >= 4 {
        for i in 0..<4 {
          av1_partition_push_child(out, av1_partition_child(node, node.row + i * quarter, node.col, quarter))
        }
      }
    }
    Av1SbPartitionVert4 => {
      let quarter = node.size / 4
      if quarter >= 4 {
        for i in 0..<4 {
          av1_partition_push_child(out, av1_partition_child(node, node.row, node.col + i * quarter, quarter))
        }
      }
    }
  }
  out
}
