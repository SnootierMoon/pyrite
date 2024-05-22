#version 330 core

vec3[] points = vec3[8](
  vec3(0, 0, 0), vec3(0, 0, 1), vec3(0, 1, 0), vec3(0, 1, 1),
  vec3(1, 0, 0), vec3(1, 0, 1), vec3(1, 1, 0), vec3(1, 1, 1)
);

uint[] face_map = uint[64](
   6U,  7U,  4U,  4U,  7U,  5U, -1U, -1U, // +x
   3U,  7U,  2U,  2U,  7U,  6U, -1U, -1U, // +y
   5U,  7U,  1U,  1U,  7U,  3U, -1U, -1U, // +z
  -1U, -1U, -1U, -1U, -1U, -1U, -1U, -1U,
   0U,  1U,  2U,  2U,  1U,  3U, -1U, -1U, // -x
   0U,  4U,  1U,  1U,  4U,  5U, -1U, -1U, // -y
   0U,  2U,  4U,  4U,  2U,  6U, -1U, -1U, // -z
  -1U, -1U, -1U, -1U, -1U, -1U, -1U, -1U
);

vec3[] colors = vec3[16](
  vec3(0.949, 0.753, 0.635), vec3(0.913, 0.518, 0.447), vec3(0.847, 0.137, 0.137), vec3(0.596, 0.094, 0.235),
  vec3(0.122, 0.796, 0.137), vec3(0.071, 0.427, 0.188), vec3(0.149, 0.867, 0.867), vec3(0.094, 0.404, 0.627),
  vec3(0.576, 0.259, 0.149), vec3(0.424, 0.145, 0.118), vec3(0.969, 0.886, 0.420), vec3(0.929, 0.698, 0.161),
  vec3(0.906, 0.427, 0.082), vec3(0.949, 0.949, 0.976), vec3(0.416, 0.498, 0.627), vec3(0.086, 0.078, 0.137)
);

uniform mat4 transform;

layout (location = 0) in uint pos;
out vec3 f_color;

void main() {
  vec3 chunk_offset = vec3(
    float(pos          & 31U),
    float((pos >> 5U)  & 31U),
    float((pos >> 10U) & 31U)
  );
  vec3 face_offset = points[face_map[((pos >> 12U) & 070U) | uint(gl_VertexID)]];
  gl_Position = transform * vec4(chunk_offset + face_offset, 1);
  f_color = colors[(int(pos) >> 15) + ((gl_VertexID + 5) & 8)];
}
