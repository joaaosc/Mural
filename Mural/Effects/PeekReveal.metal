#include <metal_stdlib>

using namespace metal;

/// Revela a camada da esquerda para a direita, com uma borda suave.
/// `progress` vai de 0 (nada visível) a 1 (tudo visível); `width` é a largura da
/// camada e `feather`, a largura da borda suave, ambas em pontos.
[[ stitchable ]] half4 muralPeekReveal(float2 position, half4 color, float width, float feather, float progress) {
    float edge = mix(-feather, width, progress);
    float visibility = 1.0 - smoothstep(edge, edge + feather, position.x);
    return color * half(visibility);
}
