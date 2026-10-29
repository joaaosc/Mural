#include <metal_stdlib>

using namespace metal;

/// Distorção de "puxar" a imagem para o ponteiro enquanto o cartão encolhe sobre uma pasta.
/// `position` é o ponto de saída, `size` o tamanho do cartão e `anchor` o ponteiro, ambos em
/// pontos do cartão (a âncora pode cair fora dele, nos cartões de um grupo). `progress` vai de
/// 0 (cartão inteiro) a 1 (encolhido); a força é máxima no meio (`sin(π·progress)`) e nula nas
/// pontas, então o cartão parado nunca fica distorcido. Devolve o ponto da imagem original que
/// aparece em `position`: amostrar mais longe da âncora faz a imagem parecer sugada para ela.
[[ stitchable ]] float2 muralFolderHoverPinch(float2 position, float2 size, float2 anchor, float progress) {
    float strength = sin(M_PI_F * clamp(progress, 0.0, 1.0));
    float2 offset = position - anchor;
    float reach = max(length(size), 1.0);
    // Perto do ponteiro a sucção é maior; nas bordas, mais suave.
    float falloff = 1.0 - 0.5 * clamp(length(offset) / reach, 0.0, 1.0);
    return anchor + offset * (1.0 + 0.35 * strength * falloff);
}
