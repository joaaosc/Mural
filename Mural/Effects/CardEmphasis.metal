#include <metal_stdlib>

using namespace metal;

/// Cor pré-multiplicada: aproxima o pixel da cor do mural sem tornar o cartão transparente.
[[ stitchable ]] half4 muralCardEmphasis(float2 position, half4 color, half4 canvas, float emphasis) {
    half amount = half(clamp(emphasis, 0.0f, 1.0f));
    return half4(mix(canvas.rgb * color.a, color.rgb, amount), color.a);
}
