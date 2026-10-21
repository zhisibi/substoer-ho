/**
 * 文件说明：应用的全局页面背景。
 *
 * 职责：按设置绘制纯色 / 渐变预设 / 用户自选图片背景，并可叠加“沉浸光感”主题色光晕。
 * 主要组件：AppBackdrop（背景组件）、pageBackdrop（供 NavDestination 使用的 @Builder）。
 * 使用位置：pages/Index.ets 在根 Navigation 下方放一份 AppBackdrop；各详情页（LogPage、EditorPage、
 *   CronEditPage、MiscPages、PanelPages 等）的 NavDestination 用 .background(pageBackdrop) 再画一份。
 * 毛玻璃：卡片 / 底栏 / 侧栏使用半透明底色 + backdropBlur，模糊的正是这里画出的背景，
 *   所以背景越有层次（图片、渐变、光晕），毛玻璃效果越明显。
 */
import { Store } from '../common/Store';
import { BackdropDef, withAlpha } from '../common/Theme';

/**
 * Page background: plain color, a gradient preset or the user's picture, plus the optional
 * "沉浸光感" (immersive light) glow tinted with the accent color.
 *
 * Drawn once under the root Navigation and behind every NavDestination (via `.background(pageBackdrop)`),
 * so pushed pages stay opaque while sharing the same look.
 */
// 中文：背景组件。层次自下而上：底色 → 图片 + 遮罩 或 渐变 → 可选光晕。
// 所有数据都来自 Store（bgKey / bgImage / glass / glow / 调色板），设置页修改后自动重绘。
@ComponentV2
export struct AppBackdrop {
  // 全局 Store 单例，读取背景与主题设置
  private store: Store = Store.get();

  // 中文：把渐变预设转换成 linearGradient 需要的 [颜色, 位置] 数组。
  // - 参数 b：背景预设，stops(isDark) 按深浅色模式给出三个颜色；
  // - 第二个色标放在 0.55 而不是 0.5，让中间色更多地占据页面上半部分（内容最密集的区域）。
  gradient(b: BackdropDef): Array<[ResourceColor, number]> {
    const c = b.stops(this.store.isDark());
    return [[c[0], 0], [c[1], 0.55], [c[2], 1]];
  }

  build() {
    // 整个背景是一个铺满的 Stack；最外层设置 hitTestBehavior(Transparent)，
    // 让触摸事件穿透背景到达上层内容，背景本身不拦截任何手势。
    Stack() {
      // Base color (also visible while a picture loads)
      Column().width('100%').height('100%').backgroundColor(this.store.palette().bg)

      // 中文：图片背景（bgImage 是复制到应用沙箱内的文件路径，所以前面拼 file://）。
      // draggable(false) 防止长按图片触发系统拖拽。下面的遮罩透明度：开启毛玻璃时遮罩更淡，
      // 因为卡片自身已有模糊和半透明底色保证可读性；关闭毛玻璃时遮罩更浓，直接压暗/提亮图片。
      if (this.store.bgKey === 'image' && this.store.bgImage.length > 0) {
        Image('file://' + this.store.bgImage)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .draggable(false)
          
        // Scrim in the page color keeps text readable on any picture
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(withAlpha(this.store.palette().bg, this.store.glass ? (this.store.isDark() ? 0.5 : 0.55) : (this.store.isDark() ? 0.72 : 0.78)))
      // 中文：渐变预设背景（backdrop() 为 null 表示纯色，只保留底色层）
      } else if (this.store.backdrop() !== null) {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({ angle: 160, colors: this.gradient(this.store.backdrop() as BackdropDef) })
      }

      // 中文：“沉浸光感”：两个径向渐变光源（左上主题色、右侧信息色），由不透明渐变到完全透明；
      // 深色模式下光源略强，否则在暗底上几乎看不出来。
      if (this.store.glow) {
        // Two soft light sources in the accent color: top left and right edge
        Column()
          .width('100%')
          .height('100%')
          .radialGradient({
            center: ['18%', '0%'],
            radius: '75%',
            colors: [[withAlpha(this.store.palette().accentFill, this.store.isDark() ? 0.30 : 0.24), 0],
              [withAlpha(this.store.palette().accentFill, 0), 1]]
          })
        Column()
          .width('100%')
          .height('100%')
          .radialGradient({
            center: ['100%', '38%'],
            radius: '60%',
            colors: [[withAlpha(this.store.palette().info, this.store.isDark() ? 0.18 : 0.12), 0],
              [withAlpha(this.store.palette().info, 0), 1]]
          })
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }
}

/** For `.background(pageBackdrop)` on NavDestinations */
// 中文：全局 @Builder，用法 NavDestination().background(pageBackdrop)。
// 为什么详情页还要再画一份背景：NavDestination 默认不透明且盖住根页面，若设为透明，
// 转场时会看到下层页面的内容；各自画一份同样的背景，既保持页面不透明，又视觉一致。
@Builder
export function pageBackdrop() {
  AppBackdrop()
}
