#version 300 es
    precision highp float;
    
    in vec2 v_texcoord;
    uniform sampler2D tex;
    out vec4 fragColor;
    
    void main() {
        vec4 pixColor = texture(tex, v_texcoord);
        vec4 color = vec4(0.9, 0.4, 0.3, 1.0); 
        fragColor = mix(pixColor, color, 0.25);
    }
