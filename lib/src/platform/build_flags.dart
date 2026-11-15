/// 平台构建旗标（组件库侧桩）。
///
/// 源仓库的 TV 构建用 `kTvBuild` 把各处高斯模糊 sigma 钳到 [kTvMaxBlurSigma]
/// 以内（低端 Mali GPU 上全屏模糊是主要掉帧源）。组件库不绑定任何宿主
/// flavor，故改用独立 `--dart-define=AMLL_TV=true`；未定义时 [tvBlurSigma]
/// 恒等返回原值，与源仓库非 TV 构建逐字一致。
library;

/// 是否 TV 构建。默认 false；AOT 下 const 分支会被树摇剔除。
const bool kTvBuild = bool.fromEnvironment('AMLL_TV');

/// TV 弱 GPU 设备的模糊上限（sigma）。
const double kTvMaxBlurSigma = 12.0;

/// TV 可读字号下限（源仓库同款常量，供布局侧按需引用）。
const double kTvMinTextScale = 1.15;

/// 按构建旗标钳制模糊 sigma；非 TV 构建恒等返回。
double tvBlurSigma(double sigma) {
  if (!kTvBuild) return sigma;
  return sigma > kTvMaxBlurSigma ? kTvMaxBlurSigma : sigma;
}
