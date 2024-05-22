#version 330 core

vec2[] points_px = vec2[12](
  vec2(25.0, 5.0),  vec2(-25.0, 5.0), vec2(25.0, -5.0),
  vec2(25.0, -5.0), vec2(-25.0, 5.0), vec2(-25.0, -5.0),
  vec2(5.0, 25.0),  vec2(-5.0, 25.0), vec2(5.0, -25.0),
  vec2(5.0, -25.0), vec2(-5.0, 25.0), vec2(-5.0, -25.0)
);

uniform vec2 frame_size;

void main() {
    gl_Position = vec4(points_px[gl_VertexID] / frame_size, 0.0, 1.0);
}
