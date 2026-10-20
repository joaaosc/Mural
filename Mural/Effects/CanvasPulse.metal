#include <metal_stdlib>

using namespace metal;

/// Filtra apenas a camada translúcida decorativa fornecida pelo SwiftUI.
/// `progress` move uma crista suave uma única vez pela viewport; o envelope
/// mantém a camada transparente antes e depois da trilha de keyframes.
[[ stitchable ]] half4 muralCanvasPulse(float2 position, half4 color, float2 size, float progress) {
    float envelope = smoothstep(0.0, 0.035, progress) * (1.0 - smoothstep(0.88, 1.0, progress));
    float crestPosition = progress * size.x;
    float distanceFromCrest = (position.x - crestPosition) / 180.0;
    float crest = exp(-distanceFromCrest * distanceFromCrest);
    float intensity = envelope * crest;

    return half4(color.rgb * half(intensity), color.a * half(intensity));
}
