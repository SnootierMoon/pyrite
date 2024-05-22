#version 330

uniform mat4 transform;

layout(location = 0) in vec2 pos;
layout(location = 1) in vec2 uv;
layout(location = 2) in vec4 color;
out vec2 frag_uv;
out vec4 frag_color;

void main() {
   frag_uv = uv;
   frag_color = color;
   gl_Position = transform * vec4(pos, 0.0, 1.0);
};
