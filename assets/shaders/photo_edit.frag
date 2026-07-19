#include <flutter/runtime_effect.glsl>

// ─── Uniform 参数 ───
uniform vec2 uResolution;    // 图片分辨率
uniform sampler2D uTexture;  // 输入图像纹理

// 基础调整
uniform float uExposure;     // -2.0 ~ +2.0 EV
uniform float uContrast;     // -100 ~ +100 → 归一化到 -1.0 ~ +1.0
uniform float uHighlights;   // -100 ~ +100 → 归一化
uniform float uShadows;      // -100 ~ +100 → 归一化
uniform float uWhites;       // -100 ~ +100 → 归一化
uniform float uBlacks;       // -100 ~ +100 → 归一化

// 色彩调整
uniform float uSaturation;   // -100 ~ +100 → 归一化
uniform float uVibrance;     // -100 ~ +100 → 归一化
uniform float uTemperature;  // -100 ~ +100 → 归一化
uniform float uTint;         // -100 ~ +100 → 归一化

// 效果
uniform float uVignette;     // -100 ~ +100 → 归一化
uniform float uGrain;        // 0 ~ 100 → 归一化到 0 ~ 1.0
uniform float uFade;         // 0 ~ 100 → 归一化到 0 ~ 1.0

out vec4 fragColor;

// ─── 辅助函数 ───

// RGB ↔ HSV 转换
vec3 rgb2hsv(vec3 c) {
  vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
  vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
  vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
  float d = q.x - min(q.w, q.y);
  float e = 1.0e-10;
  return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
  vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
  return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// 简单哈希噪声（用于颗粒效果）
float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uResolution;
  
  // Flutter 的 FlutterFragCoord() 原点在左上角，Y 轴向下，
  // 与 sampler2D 的纹理坐标（原点左下角，Y 轴向上）方向相反。
  // 但 Flutter 的 FragmentShader 已自动处理了这个差异，
  // 不需要手动翻转 Y 轴。
  
  vec4 color = texture(uTexture, uv);
  vec3 rgb = color.rgb;

  // ─── 1. 曝光 ───
  // 曝光每 +1 EV = 亮度 ×2，每 -1 EV = 亮度 ×0.5
  rgb *= pow(2.0, uExposure);

  // ─── 2. 对比度 ───
  // 以 0.5 为中心拉伸/压缩
  float contrastFactor = 1.0 + uContrast * 0.01;
  rgb = (rgb - 0.5) * contrastFactor + 0.5;

  // ─── 3. 高光/阴影 ───
  // 高光：亮度 > 0.5 的区域受影响更大
  float lum = dot(rgb, vec3(0.299, 0.587, 0.114));
  float highlightMask = smoothstep(0.5, 1.0, lum);
  rgb += uHighlights * 0.01 * highlightMask;
  
  // 阴影：亮度 < 0.5 的区域受影响更大
  float shadowMask = 1.0 - smoothstep(0.0, 0.5, lum);
  rgb += uShadows * 0.01 * shadowMask;

  // ─── 4. 白色/黑色色阶 ───
  float whiteMask = smoothstep(0.7, 1.0, lum);
  rgb += uWhites * 0.01 * whiteMask;
  
  float blackMask = 1.0 - smoothstep(0.0, 0.3, lum);
  rgb += uBlacks * 0.01 * blackMask;

  // ─── 5. 色温/色调 ───
  // 色温：正=暖（加红减蓝），负=冷（加蓝减红）
  rgb.r += uTemperature * 0.003;
  rgb.b -= uTemperature * 0.003;
  
  // 色调：正=洋红（加红减绿），负=绿（加绿减洋红）
  rgb.r += uTint * 0.002;
  rgb.g -= uTint * 0.002;
  rgb.b += uTint * 0.002;

  // ─── 6. 饱和度 ───
  vec3 hsv = rgb2hsv(rgb);
  hsv.y *= 1.0 + uSaturation * 0.01;
  rgb = hsv2rgb(hsv);

  // ─── 7. 自然饱和度（Vibrance） ───
  // 对低饱和度区域影响更大，保护已有高饱和度
  float sat = hsv.y;
  float vibranceFactor = uVibrance * 0.01;
  float vibranceMask = 1.0 - sat;
  hsv.y += vibranceFactor * vibranceMask;
  hsv.y = clamp(hsv.y, 0.0, 1.0);
  rgb = hsv2rgb(hsv);

  // ─── 8. 褪色 ───
  // 提升暗部，降低对比度，营造褪色胶片感
  rgb = mix(rgb, vec3(dot(rgb, vec3(0.299, 0.587, 0.114))), uFade * 0.3);
  rgb += uFade * 0.005;

  // ─── 9. 暗角 ───
  // 距离中心越远越暗/越亮
  vec2 center = vec2(0.5);
  float dist = distance(uv, center);
  float vignetteMask = smoothstep(0.3, 0.8, dist);
  rgb += uVignette * 0.01 * vignetteMask;

  // ─── 10. 颗粒 ───
  if (uGrain > 0.001) {
    float noise = hash(uv * uResolution * 0.5 + vec2(0.0, 1.0));
    noise = (noise - 0.5) * uGrain * 0.02;
    rgb += noise;
  }

  // Clamp 防止溢出
  rgb = clamp(rgb, 0.0, 1.0);

  fragColor = vec4(rgb, color.a);
}
